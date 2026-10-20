#include "meowo_core.h"

#include "mupdf_import.h"

#include <iomanip>
#include <nlohmann/json.hpp>
#include <sqlite3.h>

#include <fcntl.h>
#include <sys/file.h>
#include <unistd.h>

#include <algorithm>
#include <array>
#include <atomic>
#include <cerrno>
#include <chrono>
#include <cmath>
#include <cctype>
#include <cstdint>
#include <cstdlib>
#include <cstring>
#include <filesystem>
#include <fstream>
#include <map>
#include <memory>
#include <mutex>
#include <optional>
#include <random>
#include <sstream>
#include <stdexcept>
#include <string>
#include <unordered_map>
#include <utility>
#include <vector>

namespace fs = std::filesystem;
using json = nlohmann::json;

namespace meowo {
namespace {

constexpr int kSchemaVersion = 1;
constexpr int64_t kApplicationId = 1296383831;  // 0x4D454F57 "MEOW"
constexpr const char* kCoreVersion = "1.0.0-alpha.7";
constexpr size_t kMaxAssetBytes = 512ull * 1024ull * 1024ull;

class CoreError : public std::runtime_error {
 public:
  explicit CoreError(const std::string& message) : std::runtime_error(message) {}
};

int64_t now_ms() {
  return std::chrono::duration_cast<std::chrono::milliseconds>(
             std::chrono::system_clock::now().time_since_epoch())
      .count();
}

std::string random_hex(size_t bytes) {
  static thread_local std::mt19937_64 rng(std::random_device{}());
  static constexpr char kHex[] = "0123456789abcdef";
  std::string out;
  out.reserve(bytes * 2);
  for (size_t i = 0; i < bytes; ++i) {
    const uint8_t v = static_cast<uint8_t>(rng() & 0xff);
    out.push_back(kHex[v >> 4]);
    out.push_back(kHex[v & 0x0f]);
  }
  return out;
}

std::string new_id(const std::string& prefix) {
  return prefix + "_" + std::to_string(now_ms()) + "_" + random_hex(8);
}

bool safe_id(const std::string& id) {
  if (id.empty() || id.size() > 160) return false;
  for (char c : id) {
    if (!((c >= 'a' && c <= 'z') || (c >= 'A' && c <= 'Z') ||
          (c >= '0' && c <= '9') || c == '_' || c == '-')) {
      return false;
    }
  }
  return true;
}

std::string dump_json(const json& value) {
  return value.dump(-1, ' ', false, json::error_handler_t::replace);
}

void ensure_dir(const fs::path& path) {
  std::error_code ec;
  fs::create_directories(path, ec);
  if (ec) throw CoreError("无法创建目录: " + path.string() + " (" + ec.message() + ")");
}

std::string read_file(const fs::path& path) {
  std::ifstream in(path, std::ios::binary);
  if (!in) throw CoreError("无法读取文件: " + path.string());
  std::ostringstream ss;
  ss << in.rdbuf();
  if (!in.good() && !in.eof()) throw CoreError("读取文件失败: " + path.string());
  return ss.str();
}

/* ------------------------------------------------------------------------- */
/* SQLite helpers                                                            */
/* ------------------------------------------------------------------------- */

class Statement {
 public:
  Statement(sqlite3* db, const char* sql) : db_(db) {
    const int rc = sqlite3_prepare_v2(db_, sql, -1, &stmt_, nullptr);
    if (rc != SQLITE_OK) {
      throw CoreError(std::string("SQL 准备失败: ") + sqlite3_errmsg(db_));
    }
  }
  ~Statement() {
    if (stmt_) sqlite3_finalize(stmt_);
  }
  Statement(const Statement&) = delete;
  Statement& operator=(const Statement&) = delete;

  sqlite3_stmt* get() { return stmt_; }

  void bind_text(int index, const std::string& value) {
    if (sqlite3_bind_text(stmt_, index, value.c_str(),
                          static_cast<int>(value.size()), SQLITE_TRANSIENT) != SQLITE_OK) {
      throw CoreError(std::string("SQL 绑定失败: ") + sqlite3_errmsg(db_));
    }
  }
  void bind_int64(int index, int64_t value) {
    if (sqlite3_bind_int64(stmt_, index, value) != SQLITE_OK) {
      throw CoreError(std::string("SQL 绑定失败: ") + sqlite3_errmsg(db_));
    }
  }
  void bind_null(int index) {
    if (sqlite3_bind_null(stmt_, index) != SQLITE_OK) {
      throw CoreError(std::string("SQL 绑定失败: ") + sqlite3_errmsg(db_));
    }
  }
  void bind_blob(int index, const std::string& value) {
    if (sqlite3_bind_blob(stmt_, index, value.data(),
                          static_cast<int>(value.size()), SQLITE_TRANSIENT) != SQLITE_OK) {
      throw CoreError(std::string("SQL 绑定失败: ") + sqlite3_errmsg(db_));
    }
  }
  bool step_row() {
    const int rc = sqlite3_step(stmt_);
    if (rc == SQLITE_ROW) return true;
    if (rc == SQLITE_DONE) return false;
    throw CoreError(std::string("SQL 执行失败: ") + sqlite3_errmsg(db_));
  }
  void step_done() {
    const int rc = sqlite3_step(stmt_);
    if (rc != SQLITE_DONE) {
      throw CoreError(std::string("SQL 执行失败: ") + sqlite3_errmsg(db_));
    }
  }

  std::string text(int col) const {
    const unsigned char* p = sqlite3_column_text(stmt_, col);
    return p ? reinterpret_cast<const char*>(p) : std::string();
  }
  int64_t int64(int col) const { return sqlite3_column_int64(stmt_, col); }
  bool is_null(int col) const { return sqlite3_column_type(stmt_, col) == SQLITE_NULL; }

 private:
  sqlite3* db_;
  sqlite3_stmt* stmt_ = nullptr;
};

class Database {
 public:
  Database(const fs::path& path, int flags = SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE) {
    const int rc = sqlite3_open_v2(path.string().c_str(), &db_, flags | SQLITE_OPEN_FULLMUTEX,
                                   nullptr);
    if (rc != SQLITE_OK) {
      const std::string msg = db_ ? sqlite3_errmsg(db_) : "unknown";
      if (db_) sqlite3_close(db_);
      db_ = nullptr;
      throw CoreError("无法打开数据库 " + path.string() + ": " + msg);
    }
  }
  ~Database() {
    if (db_) sqlite3_close(db_);
  }
  Database(const Database&) = delete;
  Database& operator=(const Database&) = delete;
  sqlite3* get() { return db_; }

  void exec(const char* sql) {
    char* error = nullptr;
    const int rc = sqlite3_exec(db_, sql, nullptr, nullptr, &error);
    if (rc != SQLITE_OK) {
      const std::string msg = error ? error : "unknown";
      sqlite3_free(error);
      throw CoreError("SQL 执行失败: " + msg);
    }
  }

 private:
  sqlite3* db_ = nullptr;
};

class Transaction {
 public:
  explicit Transaction(Database& db) : db_(db) { db_.exec("BEGIN IMMEDIATE"); }
  ~Transaction() {
    if (!done_) {
      try {
        db_.exec("ROLLBACK");
      } catch (...) {
      }
    }
  }
  void commit() {
    db_.exec("COMMIT");
    done_ = true;
  }

 private:
  Database& db_;
  bool done_ = false;
};

void init_document_db(Database& db) {
  db.exec("PRAGMA journal_mode=WAL;");
  db.exec("PRAGMA synchronous=FULL;");
  db.exec("PRAGMA foreign_keys=ON;");
  db.exec(("PRAGMA application_id=" + std::to_string(kApplicationId) + ";").c_str());
  db.exec(("PRAGMA user_version=" + std::to_string(kSchemaVersion) + ";").c_str());
  db.exec(
      "CREATE TABLE IF NOT EXISTS document ("
      "  id TEXT PRIMARY KEY,"
      "  version INTEGER NOT NULL,"
      "  payload TEXT NOT NULL,"
      "  updated_at INTEGER NOT NULL"
      ");"
      "CREATE TABLE IF NOT EXISTS assets ("
      "  id TEXT PRIMARY KEY,"
      "  name TEXT NOT NULL,"
      "  mime TEXT NOT NULL,"
      "  size INTEGER NOT NULL,"
      "  bytes BLOB NOT NULL"
      ");"
      "CREATE TABLE IF NOT EXISTS meta ("
      "  key TEXT PRIMARY KEY,"
      "  value TEXT NOT NULL"
      ");");
}

void init_workspace_db(Database& db) {
  db.exec("PRAGMA journal_mode=WAL;");
  db.exec("PRAGMA synchronous=FULL;");
  db.exec("PRAGMA foreign_keys=ON;");
  db.exec(
      "CREATE TABLE IF NOT EXISTS folders ("
      "  id TEXT PRIMARY KEY,"
      "  name TEXT NOT NULL,"
      "  parent_id TEXT,"
      "  created_at INTEGER NOT NULL"
      ");"
      "CREATE TABLE IF NOT EXISTS documents ("
      "  id TEXT PRIMARY KEY,"
      "  title TEXT NOT NULL,"
      "  kind TEXT NOT NULL,"
      "  created_at INTEGER NOT NULL,"
      "  updated_at INTEGER NOT NULL,"
      "  folder_id TEXT,"
      "  favorite INTEGER NOT NULL DEFAULT 0,"
      "  deleted_at INTEGER,"
      "  last_opened INTEGER,"
      "  cover_asset_id TEXT"
      ");"
      "CREATE TABLE IF NOT EXISTS settings ("
      "  key TEXT PRIMARY KEY,"
      "  value TEXT NOT NULL"
      ");");
}

std::string base64_encode(const std::string& data) {
  static constexpr char kTable[] =
      "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/";
  std::string out;
  out.reserve(((data.size() + 2) / 3) * 4);
  size_t i = 0;
  while (i + 2 < data.size()) {
    const uint32_t n = (static_cast<uint8_t>(data[i]) << 16) |
                       (static_cast<uint8_t>(data[i + 1]) << 8) |
                       static_cast<uint8_t>(data[i + 2]);
    out.push_back(kTable[(n >> 18) & 63]);
    out.push_back(kTable[(n >> 12) & 63]);
    out.push_back(kTable[(n >> 6) & 63]);
    out.push_back(kTable[n & 63]);
    i += 3;
  }
  if (i < data.size()) {
    uint32_t n = static_cast<uint32_t>(static_cast<uint8_t>(data[i])) << 16;
    if (i + 1 < data.size()) n |= static_cast<uint32_t>(static_cast<uint8_t>(data[i + 1])) << 8;
    out.push_back(kTable[(n >> 18) & 63]);
    out.push_back(kTable[(n >> 12) & 63]);
    out.push_back(i + 1 < data.size() ? kTable[(n >> 6) & 63] : '=');
    out.push_back('=');
  }
  return out;
}

std::string base64_decode(const std::string& text) {
  std::array<int, 256> table;
  table.fill(-1);
  static constexpr char kTable[] =
      "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/";
  for (int i = 0; i < 64; ++i) table[static_cast<uint8_t>(kTable[i])] = i;
  std::string out;
  out.reserve(text.size() * 3 / 4);
  int value = 0;
  int bits = -8;
  for (unsigned char c : text) {
    if (c == '=') break;
    const int d = table[c];
    if (d < 0) {
      if (c == '\n' || c == '\r' || c == ' ' || c == '\t') continue;
      throw CoreError("附件 base64 数据无效");
    }
    value = (value << 6) + d;
    bits += 6;
    if (bits >= 0) {
      out.push_back(static_cast<char>((value >> bits) & 0xff));
      bits -= 8;
    }
  }
  return out;
}

std::pair<int, int> png_size(const fs::path& path) {
  std::ifstream in(path, std::ios::binary);
  if (!in) throw CoreError("无法读取 PNG: " + path.string());
  unsigned char header[24]{};
  in.read(reinterpret_cast<char*>(header), sizeof(header));
  if (in.gcount() != static_cast<std::streamsize>(sizeof(header))) {
    throw CoreError("PNG 文件过短: " + path.string());
  }
  static constexpr unsigned char kSignature[8] = {137, 80, 78, 71, 13, 10, 26, 10};
  if (std::memcmp(header, kSignature, 8) != 0) {
    throw CoreError("不是有效 PNG: " + path.string());
  }
  const int width = (header[16] << 24) | (header[17] << 16) | (header[18] << 8) | header[19];
  const int height = (header[20] << 24) | (header[21] << 16) | (header[22] << 8) | header[23];
  return {width, height};
}

/* ------------------------------------------------------------------------- */
/* Document persistence                                                      */
/* ------------------------------------------------------------------------- */

fs::path document_path(const fs::path& root, const std::string& id) {
  if (!safe_id(id)) throw CoreError("文档 ID 非法");
  return root / "documents" / (id + ".meowo");
}

json load_document_payload(const fs::path& path) {
  if (!fs::exists(path)) throw CoreError("文档不存在: " + path.string());
  Database db(path, SQLITE_OPEN_READONLY);
  Statement stmt(db.get(), "SELECT payload FROM document LIMIT 1;");
  if (!stmt.step_row()) throw CoreError("文档数据库为空");
  return json::parse(stmt.text(0));
}

void save_document_payload(const fs::path& path, const json& payload) {
  ensure_dir(path.parent_path());
  Database db(path);
  init_document_db(db);
  Transaction tx(db);
  Statement stmt(
      db.get(),
      "INSERT INTO document(id, version, payload, updated_at) VALUES(?, ?, ?, ?)"
      " ON CONFLICT(id) DO UPDATE SET version=excluded.version, payload=excluded.payload,"
      " updated_at=excluded.updated_at;");
  const std::string id = payload.value("id", "");
  if (!safe_id(id)) throw CoreError("文档 ID 非法");
  stmt.bind_text(1, id);
  stmt.bind_int64(2, payload.value("schema", kSchemaVersion));
  stmt.bind_text(3, dump_json(payload));
  stmt.bind_int64(4, now_ms());
  stmt.step_done();
  tx.commit();
}

void save_asset(const fs::path& path, const std::string& id, const std::string& name,
                const std::string& mime, const std::string& bytes) {
  Database db(path);
  init_document_db(db);
  Transaction tx(db);
  Statement stmt(
      db.get(),
      "INSERT INTO assets(id, name, mime, size, bytes) VALUES(?, ?, ?, ?, ?)"
      " ON CONFLICT(id) DO UPDATE SET name=excluded.name, mime=excluded.mime,"
      " size=excluded.size, bytes=excluded.bytes;");
  stmt.bind_text(1, id);
  stmt.bind_text(2, name);
  stmt.bind_text(3, mime);
  stmt.bind_int64(4, static_cast<int64_t>(bytes.size()));
  stmt.bind_blob(5, bytes);
  stmt.step_done();
  tx.commit();
}

json load_asset(const fs::path& path, const std::string& id) {
  Database db(path, SQLITE_OPEN_READONLY);
  Statement stmt(db.get(), "SELECT name, mime, size, bytes FROM assets WHERE id=?;");
  stmt.bind_text(1, id);
  if (!stmt.step_row()) throw CoreError("资源不存在: " + id);
  json result;
  result["id"] = id;
  result["name"] = stmt.text(0);
  result["mime"] = stmt.text(1);
  result["size"] = stmt.int64(2);
  const void* blob = sqlite3_column_blob(stmt.get(), 3);
  const int n = sqlite3_column_bytes(stmt.get(), 3);
  const std::string bytes(static_cast<const char*>(blob), static_cast<size_t>(n));
  result["base64"] = base64_encode(bytes);
  return result;
}

json layer_json(int index) {
  return json{{"id", new_id("layer")},
              {"name", "图层 " + std::to_string(index + 1)},
              {"visible", true},
              {"locked", false},
              {"opacity", 1.0},
              {"elements", json::array()}};
}

json page_json(double width, double height) {
  return json{{"id", new_id("page")},
              {"sourceIndex", nullptr},
              {"sourceAssetId", nullptr},
              {"isNotePage", true},
              {"width", width},
              {"height", height},
              {"layers", json::array({layer_json(0)})},
              {"body", nullptr}};
}

struct Paper {
  std::string preset;
  double width;
  double height;
  std::string background;
};

Paper paper_from_request(const json& request) {
  Paper paper{"A4", 595.276, 841.89, "blank"};
  const json p = request.value("paper", json::object());
  const std::string preset = p.value("preset", "A4");
  paper.preset = preset;
  paper.background = p.value("background", "blank");
  const std::map<std::string, std::pair<double, double>> presets = {
      {"A4", {595.276, 841.89}}, {"A5", {419.528, 595.276}},
      {"B5", {498.898, 708.661}}, {"Letter", {612.0, 792.0}},
      {"Legal", {612.0, 1008.0}}};
  if (preset == "custom") {
    double mm_w = p.value("widthMm", 210.0);
    double mm_h = p.value("heightMm", 297.0);
    mm_w = std::clamp(mm_w, 50.0, 2000.0);
    mm_h = std::clamp(mm_h, 50.0, 2000.0);
    paper.width = mm_w * 72.0 / 25.4;
    paper.height = mm_h * 72.0 / 25.4;
  } else {
    const auto it = presets.find(preset);
    if (it == presets.end()) throw CoreError("未知纸张预设: " + preset);
    paper.width = it->second.first;
    paper.height = it->second.second;
  }
  if (p.value("landscape", false)) std::swap(paper.width, paper.height);
  return paper;
}

json make_document(const std::string& id, const std::string& title, const std::string& kind,
                   const Paper& paper) {
  const int64_t stamp = now_ms();
  json doc;
  doc["schema"] = 1;
  doc["id"] = id;
  doc["title"] = title;
  doc["kind"] = kind;
  doc["createdAt"] = stamp;
  doc["updatedAt"] = stamp;
  doc["paper"] = {{"preset", paper.preset},
                  {"width", paper.width},
                  {"height", paper.height},
                  {"background", paper.background}};
  doc["chapters"] = json::array();
  doc["assets"] = json::array();
  if (kind == "infinite") {
    json page = page_json(1600.0, 1200.0);
    page["isNotePage"] = false;
    doc["pages"] = json::array({page});
  } else {
    doc["pages"] = json::array({page_json(paper.width, paper.height)});
  }
  return doc;
}

std::string title_from_path(const fs::path& path) {
  std::string name = path.stem().string();
  if (name.empty()) name = "未命名";
  return name;
}

std::string searchable_text(const json& doc) {
  std::string text = doc.value("title", "");
  text.push_back('\n');
  for (const auto& page : doc.value("pages", json::array())) {
    if (!page.is_object()) continue;
    const auto body = page.find("body");
    if (body != page.end() && body->is_object()) {
      text += body->value("markdown", "");
      text.push_back('\n');
    }
    text += page.value("sourceText", "");
    text.push_back('\n');
    for (const auto& layer : page.value("layers", json::array())) {
      if (!layer.is_object()) continue;
      for (const auto& element : layer.value("elements", json::array())) {
        if (!element.is_object()) continue;
        const std::string type = element.value("type", "");
        if (type == "text") {
          text += element.value("markdown", "");
          text.push_back('\n');
        } else if (type == "attachment") {
          text += element.value("name", "");
          text.push_back('\n');
        }
      }
    }
  }
  for (const auto& asset : doc.value("assets", json::array())) {
    if (asset.is_object()) {
      text += asset.value("name", "");
      text.push_back('\n');
    }
  }
  return text;
}

/* ------------------------------------------------------------------------- */
/* Workspace                                                                */
/* ------------------------------------------------------------------------- */

class Workspace {
 public:
  explicit Workspace(fs::path root)
      : root_(std::move(root)), db_(root_ / "workspace.sqlite") {
    ensure_dir(root_);
    ensure_dir(root_ / "documents");
    ensure_dir(root_ / "cache");
    acquire_lock();
    init_workspace_db(db_);
  }

  const fs::path& root() const { return root_; }
  sqlite3* db() { return db_.get(); }

  json invoke(const json& request) {
    const std::string op = request.value("op", "");
    if (op == "workspace_info") return workspace_info();
    if (op == "list_documents") return list_documents(request);
    if (op == "create_document") return create_document(request);
    if (op == "open_document") return open_document(request);
    if (op == "save_document") return save_document(request);
    if (op == "rename_document") return rename_document(request);
    if (op == "toggle_favorite") return toggle_favorite(request);
    if (op == "move_document") return move_document(request);
    if (op == "delete_document") return delete_document(request);
    if (op == "restore_document") return restore_document(request);
    if (op == "purge_document") return purge_document(request);
    if (op == "search") return search(request);
    if (op == "list_folders") return list_folders();
    if (op == "create_folder") return create_folder(request);
    if (op == "rename_folder") return rename_folder(request);
    if (op == "delete_folder") return delete_folder(request);
    if (op == "add_asset") return add_asset(request);
    if (op == "get_asset") return get_asset(request);
    if (op == "list_assets") return list_assets(request);
    if (op == "delete_asset") return delete_asset(request);
    if (op == "import_markdown") return import_markdown(request);
    if (op == "import_pdf") return import_pdf(request);
    if (op == "import_epub") return import_epub(request);
    if (op == "import_pdf_pages") return import_pdf_pages(request);
    if (op == "export_document") return export_document(request);
    if (op == "statistics") return statistics();
    throw CoreError("未知操作: " + op);
  }

 private:
  json workspace_info() {
    Statement count(db_.get(), "SELECT COUNT(*) FROM documents WHERE deleted_at IS NULL;");
    count.step_row();
    return json{{"root", root_.string()},
                {"documentCount", count.int64(0)},
                {"schema", kSchemaVersion},
                {"version", kCoreVersion}};
  }

  void insert_catalog(const json& doc, const std::optional<std::string>& folder_id = std::nullopt) {
    Statement stmt(
        db_.get(),
        "INSERT INTO documents(id,title,kind,created_at,updated_at,folder_id,favorite,cover_asset_id)"
        " VALUES(?,?,?,?,?,?,?,?);");
    stmt.bind_text(1, doc.value("id", ""));
    stmt.bind_text(2, doc.value("title", "未命名"));
    stmt.bind_text(3, doc.value("kind", "paged"));
    stmt.bind_int64(4, doc.value("createdAt", now_ms()));
    stmt.bind_int64(5, doc.value("updatedAt", now_ms()));
    if (folder_id && safe_id(*folder_id)) {
      stmt.bind_text(6, *folder_id);
    } else {
      stmt.bind_null(6);
    }
    stmt.bind_int64(7, 0);
    stmt.bind_null(8);
    stmt.step_done();
  }

  json document_row(Statement& stmt) {
    json item;
    item["id"] = stmt.text(0);
    item["title"] = stmt.text(1);
    item["kind"] = stmt.text(2);
    item["createdAt"] = stmt.int64(3);
    item["updatedAt"] = stmt.int64(4);
    item["folderId"] = stmt.is_null(5) ? json(nullptr) : json(stmt.text(5));
    item["favorite"] = stmt.int64(6) != 0;
    item["deletedAt"] = stmt.is_null(7) ? json(nullptr) : json(stmt.int64(7));
    item["lastOpened"] = stmt.is_null(8) ? json(nullptr) : json(stmt.int64(8));
    return item;
  }

  json list_documents(const json& request) {
    const bool trash = request.value("trash", false);
    const bool favorites = request.value("favorites", false);
    const std::string folder = request.value("folderId", "");
    const std::string query = request.value("query", "");
    std::string sql =
        "SELECT id,title,kind,created_at,updated_at,folder_id,favorite,deleted_at,last_opened"
        " FROM documents WHERE ";
    sql += trash ? "deleted_at IS NOT NULL" : "deleted_at IS NULL";
    if (favorites) sql += " AND favorite=1";
    if (!folder.empty() && safe_id(folder)) sql += " AND folder_id=?";
    if (!query.empty()) sql += " AND title LIKE ?";
    sql += " ORDER BY updated_at DESC;";
    Statement stmt(db_.get(), sql.c_str());
    int index = 1;
    if (!folder.empty() && safe_id(folder)) stmt.bind_text(index++, folder);
    if (!query.empty()) stmt.bind_text(index++, "%" + query + "%");
    json items = json::array();
    while (stmt.step_row()) items.push_back(document_row(stmt));
    return json{{"items", items}};
  }

  json create_document(const json& request) {
    const std::string title = request.value("title", "未命名");
    const std::string kind = request.value("kind", "paged");
    if (kind != "paged" && kind != "infinite") {
      throw CoreError("首版只支持创建书页或无极文档");
    }
    const Paper paper = paper_from_request(request);
    const std::string id = new_id("doc");
    json doc = make_document(id, title, kind, paper);
    const std::string folder = request.value("folderId", "");
    if (!folder.empty() && safe_id(folder)) {
      Statement check(db_.get(), "SELECT 1 FROM folders WHERE id=?;");
      check.bind_text(1, folder);
      if (!check.step_row()) throw CoreError("文件夹不存在");
    }
    save_document_payload(document_path(root_, id), doc);
    Transaction tx(db_);
    insert_catalog(doc, folder.empty() ? std::nullopt : std::optional<std::string>(folder));
    tx.commit();
    return doc;
  }

  json open_document(const json& request) {
    const std::string id = request.value("id", "");
    const fs::path path = document_path(root_, id);
    json doc = load_document_payload(path);
    Transaction tx(db_);
    Statement stmt(db_.get(), "UPDATE documents SET last_opened=? WHERE id=?;");
    stmt.bind_int64(1, now_ms());
    stmt.bind_text(2, id);
    stmt.step_done();
    tx.commit();
    return doc;
  }

  json save_document(const json& request) {
    if (!request.contains("document") || !request["document"].is_object()) {
      throw CoreError("缺少 document");
    }
    json doc = request["document"];
    const std::string id = doc.value("id", "");
    if (!safe_id(id)) throw CoreError("文档 ID 非法");
    doc["updatedAt"] = now_ms();
    save_document_payload(document_path(root_, id), doc);
    Transaction tx(db_);
    Statement stmt(db_.get(), "UPDATE documents SET title=?, kind=?, updated_at=? WHERE id=?;");
    stmt.bind_text(1, doc.value("title", "未命名"));
    stmt.bind_text(2, doc.value("kind", "paged"));
    stmt.bind_int64(3, doc.value("updatedAt", now_ms()));
    stmt.bind_text(4, id);
    stmt.step_done();
    tx.commit();
    return json{{"savedAt", doc["updatedAt"]}};
  }

  json rename_document(const json& request) {
    const std::string id = request.value("id", "");
    const std::string title = request.value("title", "未命名");
    const fs::path path = document_path(root_, id);
    json doc = load_document_payload(path);
    doc["title"] = title;
    doc["updatedAt"] = now_ms();
    save_document_payload(path, doc);
    Transaction tx(db_);
    Statement stmt(db_.get(), "UPDATE documents SET title=?, updated_at=? WHERE id=?;");
    stmt.bind_text(1, title);
    stmt.bind_int64(2, doc["updatedAt"].get<int64_t>());
    stmt.bind_text(3, id);
    stmt.step_done();
    tx.commit();
    return json{{"id", id}, {"title", title}};
  }

  json toggle_favorite(const json& request) {
    const std::string id = request.value("id", "");
    Transaction tx(db_);
    Statement stmt(db_.get(), "UPDATE documents SET favorite=1-favorite WHERE id=?;");
    stmt.bind_text(1, id);
    stmt.step_done();
    tx.commit();
    Statement read(db_.get(), "SELECT favorite FROM documents WHERE id=?;");
    read.bind_text(1, id);
    if (!read.step_row()) throw CoreError("文档不存在");
    return json{{"id", id}, {"favorite", read.int64(0) != 0}};
  }

  json move_document(const json& request) {
    const std::string id = request.value("id", "");
    std::string folder = request.value("folderId", "");
    if (!folder.empty() && !safe_id(folder)) throw CoreError("文件夹 ID 非法");
    if (!folder.empty()) {
      Statement check(db_.get(), "SELECT 1 FROM folders WHERE id=?;");
      check.bind_text(1, folder);
      if (!check.step_row()) throw CoreError("文件夹不存在");
    }
    Transaction tx(db_);
    Statement stmt(db_.get(), "UPDATE documents SET folder_id=? WHERE id=?;");
    if (folder.empty()) {
      stmt.bind_null(1);
    } else {
      stmt.bind_text(1, folder);
    }
    stmt.bind_text(2, id);
    stmt.step_done();
    tx.commit();
    return json{{"id", id}, {"folderId", folder.empty() ? json(nullptr) : json(folder)}};
  }

  json delete_document(const json& request) {
    const std::string id = request.value("id", "");
    Transaction tx(db_);
    Statement stmt(db_.get(), "UPDATE documents SET deleted_at=? WHERE id=?;");
    stmt.bind_int64(1, now_ms());
    stmt.bind_text(2, id);
    stmt.step_done();
    tx.commit();
    return json{{"id", id}, {"deleted", true}};
  }

  json restore_document(const json& request) {
    const std::string id = request.value("id", "");
    Transaction tx(db_);
    Statement stmt(db_.get(), "UPDATE documents SET deleted_at=NULL WHERE id=?;");
    stmt.bind_text(1, id);
    stmt.step_done();
    tx.commit();
    return json{{"id", id}, {"restored", true}};
  }

  json purge_document(const json& request) {
    const std::string id = request.value("id", "");
    const fs::path path = document_path(root_, id);
    std::error_code ec;
    const bool removed = fs::remove(path, ec);
    if (ec) throw CoreError("删除文档失败: " + ec.message());
    Transaction tx(db_);
    Statement stmt(db_.get(), "DELETE FROM documents WHERE id=?;");
    stmt.bind_text(1, id);
    stmt.step_done();
    tx.commit();
    return json{{"id", id}, {"purged", removed}};
  }

  json search(const json& request) {
    const std::string query = request.value("query", "");
    if (query.empty()) return json{{"items", json::array()}};
    Statement stmt(
        db_.get(),
        "SELECT id,title,kind,created_at,updated_at,folder_id,favorite,deleted_at,last_opened"
        " FROM documents WHERE deleted_at IS NULL ORDER BY updated_at DESC;");
    json items = json::array();
    while (stmt.step_row()) {
      const std::string id = stmt.text(0);
      bool match = stmt.text(1).find(query) != std::string::npos;
      if (!match) {
        try {
          const json doc = load_document_payload(document_path(root_, id));
          match = searchable_text(doc).find(query) != std::string::npos;
        } catch (...) {
        }
      }
      if (match) items.push_back(document_row(stmt));
    }
    return json{{"items", items}};
  }

  json list_folders() {
    Statement stmt(db_.get(),
                    "SELECT id,name,parent_id,created_at FROM folders ORDER BY created_at ASC;");
    json items = json::array();
    while (stmt.step_row()) {
      items.push_back(json{{"id", stmt.text(0)},
                           {"name", stmt.text(1)},
                           {"parentId", stmt.is_null(2) ? json(nullptr) : json(stmt.text(2))},
                           {"createdAt", stmt.int64(3)}});
    }
    return json{{"items", items}};
  }

  int folder_depth(const std::string& id) {
    int depth = 0;
    std::string current = id;
    while (!current.empty()) {
      if (++depth > 3) break;
      Statement stmt(db_.get(), "SELECT parent_id FROM folders WHERE id=?;");
      stmt.bind_text(1, current);
      if (!stmt.step_row()) break;
      current = stmt.is_null(0) ? std::string() : stmt.text(0);
    }
    return depth;
  }

  json create_folder(const json& request) {
    const std::string name = request.value("name", "文件夹");
    const std::string parent = request.value("parentId", "");
    if (!parent.empty()) {
      if (!safe_id(parent)) throw CoreError("父文件夹 ID 非法");
      if (folder_depth(parent) >= 3) throw CoreError("文件夹最多 3 级");
      Statement check(db_.get(), "SELECT 1 FROM folders WHERE id=?;");
      check.bind_text(1, parent);
      if (!check.step_row()) throw CoreError("父文件夹不存在");
    }
    const std::string id = new_id("folder");
    Transaction tx(db_);
    Statement stmt(db_.get(),
                   "INSERT INTO folders(id,name,parent_id,created_at) VALUES(?,?,?,?);");
    stmt.bind_text(1, id);
    stmt.bind_text(2, name);
    if (parent.empty()) stmt.bind_null(3); else stmt.bind_text(3, parent);
    stmt.bind_int64(4, now_ms());
    stmt.step_done();
    tx.commit();
    return json{{"id", id}, {"name", name}, {"parentId", parent.empty() ? json(nullptr) : json(parent)}};
  }

  json rename_folder(const json& request) {
    const std::string id = request.value("id", "");
    const std::string name = request.value("name", "文件夹");
    Transaction tx(db_);
    Statement stmt(db_.get(), "UPDATE folders SET name=? WHERE id=?;");
    stmt.bind_text(1, name);
    stmt.bind_text(2, id);
    stmt.step_done();
    tx.commit();
    return json{{"id", id}, {"name", name}};
  }

  json delete_folder(const json& request) {
    const std::string id = request.value("id", "");
    Transaction tx(db_);
    Statement docs(db_.get(), "UPDATE documents SET folder_id=NULL WHERE folder_id=?;");
    docs.bind_text(1, id);
    docs.step_done();
    Statement children(db_.get(), "UPDATE folders SET parent_id=NULL WHERE parent_id=?;");
    children.bind_text(1, id);
    children.step_done();
    Statement stmt(db_.get(), "DELETE FROM folders WHERE id=?;");
    stmt.bind_text(1, id);
    stmt.step_done();
    tx.commit();
    return json{{"id", id}, {"deleted", true}};
  }

  json add_asset(const json& request) {
    const std::string doc_id = request.value("documentId", "");
    const std::string name = request.value("name", "file");
    const std::string mime = request.value("mime", "application/octet-stream");
    const std::string data = base64_decode(request.value("data", ""));
    if (data.size() > kMaxAssetBytes) throw CoreError("单个附件不能超过 512 MiB");
    const fs::path path = document_path(root_, doc_id);
    json doc = load_document_payload(path);
    const std::string asset_id = new_id("asset");
    save_asset(path, asset_id, name, mime, data);
    json meta{{"id", asset_id}, {"name", name}, {"mime", mime},
              {"size", data.size()}, {"kind", mime.rfind("image/", 0) == 0 ? "image" : "file"}};
    doc["assets"].push_back(meta);
    doc["updatedAt"] = now_ms();
    save_document_payload(path, doc);
    Transaction tx(db_);
    Statement stmt(db_.get(), "UPDATE documents SET updated_at=? WHERE id=?;");
    stmt.bind_int64(1, doc["updatedAt"].get<int64_t>());
    stmt.bind_text(2, doc_id);
    stmt.step_done();
    tx.commit();
    return meta;
  }

  json get_asset(const json& request) {
    const std::string doc_id = request.value("documentId", "");
    return load_asset(document_path(root_, doc_id), request.value("assetId", ""));
  }

  std::vector<std::string> find_asset_references(const json& doc, const std::string& asset_id) {
    std::vector<std::string> refs;
    const std::string link = "meowo://asset/" + asset_id;
    auto check_element = [&](const json& el, const std::string& where) {
      if (!el.is_object()) return;
      if (el.value("assetId", "") == asset_id || el.value("sourceAssetId", "") == asset_id) {
        refs.push_back(where);
      }
      if (el.contains("markdown") && el["markdown"].is_string() &&
          el["markdown"].get<std::string>().find(link) != std::string::npos) {
        refs.push_back(where + "（Markdown 链接）");
      }
    };
    if (doc.contains("bookSource") && doc["bookSource"].is_object() &&
        doc["bookSource"].value("assetId", "") == asset_id) {
      refs.push_back("书籍源文件");
    }
    int page_no = 1;
    for (const auto& page : doc.value("pages", json::array())) {
      if (page.contains("body")) check_element(page["body"], "第 " + std::to_string(page_no) + " 页 / 本底文本");
      int layer_no = 1;
      for (const auto& layer : page.value("layers", json::array())) {
        int element_no = 1;
        for (const auto& el : layer.value("elements", json::array())) {
          check_element(el, "第 " + std::to_string(page_no) + " 页 / 图层 " +
                                std::to_string(layer_no) + " / 元素 " + std::to_string(element_no));
          ++element_no;
        }
        ++layer_no;
      }
      ++page_no;
    }
    return refs;
  }

  json list_assets(const json& request) {
    const std::string doc_id = request.value("documentId", "");
    json doc = load_document_payload(document_path(root_, doc_id));
    json out = json::array();
    for (const auto& asset : doc.value("assets", json::array())) {
      json item = asset;
      const auto refs = find_asset_references(doc, asset.value("id", ""));
      item["referenced"] = !refs.empty();
      item["referenceCount"] = refs.size();
      item["references"] = refs;
      out.push_back(std::move(item));
    }
    return json{{"assets", out}};
  }

  json delete_asset(const json& request) {
    const std::string doc_id = request.value("documentId", "");
    const std::string asset_id = request.value("assetId", "");
    if (asset_id.empty()) throw CoreError("缺少资源 ID");
    const fs::path path = document_path(root_, doc_id);
    json doc = load_document_payload(path);
    const auto refs = find_asset_references(doc, asset_id);
    if (!refs.empty()) {
      throw CoreError("资源仍被引用，不能删除：" + refs.front());
    }
    bool found = false;
    json kept = json::array();
    for (const auto& asset : doc.value("assets", json::array())) {
      if (asset.value("id", "") == asset_id) {
        found = true;
      } else {
        kept.push_back(asset);
      }
    }
    if (!found) throw CoreError("资源不存在");
    doc["assets"] = std::move(kept);
    doc["updatedAt"] = now_ms();
    save_document_payload(path, doc);
    Database doc_db(path);
    Statement stmt(doc_db.get(), "DELETE FROM assets WHERE id=?;");
    stmt.bind_text(1, asset_id);
    stmt.step_done();
    return json{{"id", asset_id}, {"deleted", true}};
  }

  json import_markdown(const json& request) {
    const std::string source = request.value("sourcePath", "");
    if (source.empty()) throw CoreError("缺少 Markdown 路径");
    fs::path source_path(source);
    if (!fs::exists(source_path)) throw CoreError("Markdown 文件不存在");
    const std::string text = read_file(source_path);
    const std::string title = request.value("title", title_from_path(source_path));
    Paper paper{"A4", 595.276, 841.89, "blank"};
    const std::string id = new_id("doc");
    json doc = make_document(id, title, "paged", paper);
    json body{{"id", new_id("text")},
              {"type", "text"},
              {"layoutMode", "body"},
              {"x", 48.0}, {"y", 48.0},
              {"w", paper.width - 96.0}, {"h", paper.height - 96.0},
              {"markdown", text},
              {"fontSize", 16.0}, {"lineHeight", 1.5},
              {"color", "#222222"}, {"align", "left"},
              {"opacity", 1.0}, {"locked", false}};
    doc["pages"][0]["body"] = body;
    save_document_payload(document_path(root_, id), doc);
    Transaction tx(db_);
    insert_catalog(doc);
    tx.commit();
    return json{{"id", id}, {"title", title}, {"pages", 1}};
  }

  json import_book(const json& request, const std::string& format) {
    const std::string source = request.value("sourcePath", "");
    if (source.empty()) throw CoreError("缺少 " + format + " 路径");
    fs::path source_path(source);
    if (!fs::exists(source_path)) throw CoreError(format + " 文件不存在");

    std::error_code size_ec;
    const auto source_size = fs::file_size(source_path, size_ec);
    if (size_ec) throw CoreError("无法读取文件大小");
    if (source_size > kMaxAssetBytes) throw CoreError("原始书籍超过 512 MiB");

    const std::string id = new_id("doc");
    const fs::path temp = root_ / ".import" / id;
    ensure_dir(temp);
    struct Cleanup {
      fs::path path;
      ~Cleanup() {
        std::error_code ec;
        fs::remove_all(path, ec);
      }
    } cleanup{temp};

    MuPdfResult result;
    try {
      result = render_with_mupdf(source_path.string(), temp.string(),
                                 request.value("password", ""), 500);
    } catch (const std::exception& e) {
      throw CoreError(std::string("MuPDF 渲染失败: ") + e.what());
    }
    if (!result.ok) {
      throw CoreError(result.error.empty() ? "无法渲染书籍" : result.error);
    }
    if (result.pageCount <= 0 || result.pages.size() != static_cast<size_t>(result.pageCount)) {
      throw CoreError("MuPDF 未返回有效页面");
    }

    std::string title = request.value("title", "");
    if (title.empty()) title = result.title;
    if (format == "epub" && !title.empty()) {
      std::string lower = title;
      std::transform(lower.begin(), lower.end(), lower.begin(),
                     [](unsigned char c) { return static_cast<char>(std::tolower(c)); });
      if (lower.ends_with(".html") || lower.ends_with(".xhtml") || lower.ends_with(".htm")) {
        title.clear();
      }
    }
    if (title.empty()) title = title_from_path(source_path);

    json doc = make_document(id, title, "book", Paper{"A4", 595.276, 841.89, "blank"});
    doc["pages"] = json::array();
    doc["assets"] = json::array();
    std::vector<std::pair<std::string, std::pair<std::string, std::string>>> assets;
    double paper_width = 0;
    double paper_height = 0;
    for (int i = 0; i < result.pageCount; ++i) {
      std::ostringstream stem;
      stem << "page-" << std::setw(4) << std::setfill('0') << (i + 1);
      const fs::path png = temp / (stem.str() + ".png");
      if (!fs::exists(png)) throw CoreError("MuPDF 页面缺失: " + png.string());
      const fs::path txt = temp / (stem.str() + ".txt");
      std::string source_text;
      if (fs::exists(txt)) source_text = read_file(txt);

      const auto [pixel_w, pixel_h] = png_size(png);
      double width = result.pages[static_cast<size_t>(i)].width;
      double height = result.pages[static_cast<size_t>(i)].height;
      if (width <= 0 || height <= 0) {
        width = pixel_w * 72.0 / 120.0;
        height = pixel_h * 72.0 / 120.0;
      }
      const std::string bytes = read_file(png);
      if (bytes.size() > kMaxAssetBytes) throw CoreError("书籍页面图片超过 512 MiB");
      if (i == 0) {
        paper_width = width;
        paper_height = height;
      }
      const std::string asset_id = new_id("asset");
      assets.push_back({asset_id, {png.filename().string(), bytes}});
      json page = page_json(width, height);
      page["isNotePage"] = false;
      page["sourceIndex"] = i;
      page["sourceAssetId"] = asset_id;
      page["sourceText"] = source_text;
      doc["pages"].push_back(page);
      doc["assets"].push_back(json{{"id", asset_id},
                                   {"name", "第 " + std::to_string(i + 1) + " 页"},
                                   {"mime", "image/png"},
                                   {"size", bytes.size()},
                                   {"kind", "book_page"}});
    }

    const std::string source_asset_id = new_id("asset");
    const std::string source_mime =
        format == "epub" ? "application/epub+zip" : "application/pdf";
    const std::string source_bytes = read_file(source_path);
    assets.push_back({source_asset_id, {source_path.filename().string(), source_bytes}});
    doc["assets"].push_back(json{{"id", source_asset_id},
                                 {"name", source_path.filename().string()},
                                 {"mime", source_mime},
                                 {"size", source_bytes.size()},
                                 {"kind", "book_source"}});
    doc["bookSource"] = json{{"assetId", source_asset_id},
                             {"mime", source_mime},
                             {"engine", "mupdf"},
                             {"version", result.version},
                             {"pageCount", result.pageCount},
                             {"title", result.title},
                             {"author", result.author},
                             {"format", result.format}};
    doc["paper"]["width"] = paper_width;
    doc["paper"]["height"] = paper_height;

    const fs::path target = document_path(root_, id);
    save_document_payload(target, doc);
    for (const auto& [asset_id, payload] : assets) {
      const std::string& mime = asset_id == source_asset_id ? source_mime : "image/png";
      save_asset(target, asset_id, payload.first, mime, payload.second);
    }
    Transaction tx(db_);
    insert_catalog(doc);
    tx.commit();
    return json{{"id", id},
                {"title", title},
                {"pages", doc["pages"].size()},
                {"engine", "mupdf"},
                {"version", result.version}};
  }

  json import_pdf(const json& request) {
    return import_book(request, "pdf");
  }

  json import_epub(const json& request) {
    return import_book(request, "epub");
  }

  json import_pdf_pages(const json& request) {
    if (!request.contains("pages") || !request["pages"].is_array()) {
      throw CoreError("缺少页面列表");
    }
    const auto& pages = request["pages"];
    if (pages.empty()) throw CoreError("PDF 没有可导入页面");
    if (pages.size() > 500) throw CoreError("首版单次最多导入 500 页 PDF");
    const std::string title = request.value("title", "PDF");
    const std::string id = new_id("doc");
    json doc = make_document(id, title, "book", Paper{"A4", 595.276, 841.89, "blank"});
    doc["pages"] = json::array();
    doc["assets"] = json::array();
    std::vector<std::pair<std::string, std::pair<std::string, std::string>>> assets;
    double paper_width = 0;
    double paper_height = 0;
    for (size_t i = 0; i < pages.size(); ++i) {
      const auto& item = pages[i];
      const std::string path = item.value("path", "");
      if (path.empty() || !fs::exists(path)) {
        throw CoreError("PDF 页面图片不存在: " + path);
      }
      const auto [pixel_w, pixel_h] = png_size(path);
      double width = item.value("width", 0.0);
      double height = item.value("height", 0.0);
      if (width <= 0 || height <= 0) {
        width = pixel_w * 72.0 / 120.0;
        height = pixel_h * 72.0 / 120.0;
      }
      const std::string bytes = read_file(path);
      if (bytes.size() > kMaxAssetBytes) {
        throw CoreError("PDF 页面图片超过 512 MiB");
      }
      if (i == 0) {
        paper_width = width;
        paper_height = height;
      }
      const std::string asset_id = new_id("asset");
      assets.push_back({asset_id, {fs::path(path).filename().string(), bytes}});
      json page = page_json(width, height);
      page["isNotePage"] = false;
      page["sourceIndex"] = static_cast<int>(i);
      page["sourceAssetId"] = asset_id;
      doc["pages"].push_back(page);
      doc["assets"].push_back(json{{"id", asset_id},
                                   {"name", "第 " + std::to_string(i + 1) + " 页"},
                                   {"mime", "image/png"},
                                   {"size", bytes.size()},
                                   {"kind", "book_page"}});
    }
    doc["paper"]["width"] = paper_width;
    doc["paper"]["height"] = paper_height;
    const fs::path target = document_path(root_, id);
    save_document_payload(target, doc);
    for (const auto& [asset_id, payload] : assets) {
      save_asset(target, asset_id, payload.first, "image/png", payload.second);
    }
    Transaction tx(db_);
    insert_catalog(doc);
    tx.commit();
    return json{{"id", id}, {"title", title}, {"pages", doc["pages"].size()}};
  }

  json export_document(const json& request) {
    const std::string id = request.value("id", "");
    const std::string target = request.value("targetPath", "");
    if (target.empty()) throw CoreError("缺少导出路径");
    fs::path target_path(target);
    if (fs::exists(target_path)) throw CoreError("目标文件已存在");
    ensure_dir(target_path.parent_path());
    std::error_code ec;
    fs::copy_file(document_path(root_, id), target_path, fs::copy_options::none, ec);
    if (ec) throw CoreError("导出失败: " + ec.message());
    return json{{"path", target_path.string()}};
  }

  json statistics() {
    json result;
    Statement docs(db_.get(), "SELECT COUNT(*) FROM documents WHERE deleted_at IS NULL;");
    docs.step_row();
    result["documents"] = docs.int64(0);
    Statement trash(db_.get(), "SELECT COUNT(*) FROM documents WHERE deleted_at IS NOT NULL;");
    trash.step_row();
    result["trash"] = trash.int64(0);
    Statement folders(db_.get(), "SELECT COUNT(*) FROM folders;");
    folders.step_row();
    result["folders"] = folders.int64(0);
    return result;
  }

  struct FileLock {
    int fd = -1;
    ~FileLock() {
      if (fd >= 0) {
        ::flock(fd, LOCK_UN);
        ::close(fd);
      }
    }
  };

  void acquire_lock() {
    const fs::path path = root_ / ".meowo.lock";
    lock_.fd = ::open(path.string().c_str(), O_RDWR | O_CREAT | O_CLOEXEC, 0644);
    if (lock_.fd < 0) {
      throw CoreError("无法创建资料库锁文件: " + path.string() + " (" +
                      std::strerror(errno) + ")");
    }
    if (::flock(lock_.fd, LOCK_EX | LOCK_NB) != 0) {
      const int error = errno;
      ::close(lock_.fd);
      lock_.fd = -1;
      throw CoreError("资料库已被另一个 Meowo 实例打开: " + std::string(std::strerror(error)));
    }
  }

  fs::path root_;
  FileLock lock_;
  Database db_;
};

/* ------------------------------------------------------------------------- */
/* Handle registry                                                          */
/* ------------------------------------------------------------------------- */

std::mutex g_mutex;
std::unordered_map<uint64_t, std::unique_ptr<Workspace>> g_workspaces;
std::atomic<uint64_t> g_next_handle{1};

void set_error(char** error, const std::string& message) {
  if (!error) return;
  *error = static_cast<char*>(std::malloc(message.size() + 1));
  if (*error) std::memcpy(*error, message.c_str(), message.size() + 1);
}

}  // namespace
}  // namespace meowo

extern "C" {

const char* meowo_core_version(void) {
  return meowo::kCoreVersion;
}

uint64_t meowo_workspace_open(const char* root, char** error) {
  if (error) *error = nullptr;
  if (!root || !*root) {
    meowo::set_error(error, "资料库路径为空");
    return 0;
  }
  try {
    auto workspace = std::make_unique<meowo::Workspace>(std::filesystem::path(root));
    std::lock_guard<std::mutex> lock(meowo::g_mutex);
    const uint64_t handle = meowo::g_next_handle.fetch_add(1);
    meowo::g_workspaces[handle] = std::move(workspace);
    return handle;
  } catch (const std::exception& e) {
    meowo::set_error(error, std::string("打开资料库失败: ") + e.what());
    return 0;
  }
}

void meowo_workspace_close(uint64_t handle) {
  std::lock_guard<std::mutex> lock(meowo::g_mutex);
  meowo::g_workspaces.erase(handle);
}

char* meowo_invoke(uint64_t handle, const char* request, char** error) {
  if (error) *error = nullptr;
  if (!request) {
    meowo::set_error(error, "请求为空");
    return nullptr;
  }
  try {
    const nlohmann::json parsed = nlohmann::json::parse(request);
    meowo::Workspace* workspace = nullptr;
    {
      std::lock_guard<std::mutex> lock(meowo::g_mutex);
      const auto it = meowo::g_workspaces.find(handle);
      if (it == meowo::g_workspaces.end()) {
        meowo::set_error(error, "资料库句柄无效");
        return nullptr;
      }
      workspace = it->second.get();
    }
    const nlohmann::json result = workspace->invoke(parsed);
    const std::string text = meowo::dump_json(result);
    char* output = static_cast<char*>(std::malloc(text.size() + 1));
    if (!output) {
      meowo::set_error(error, "内存不足");
      return nullptr;
    }
    std::memcpy(output, text.c_str(), text.size() + 1);
    return output;
  } catch (const std::exception& e) {
    meowo::set_error(error, e.what());
    return nullptr;
  }
}

void meowo_free(char* ptr) {
  std::free(ptr);
}

}  // extern "C"
