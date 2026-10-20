#include "meowo_core.h"

#include <gtest/gtest.h>
#include <nlohmann/json.hpp>

#include <cstdlib>
#include <filesystem>
#include <fstream>
#include <string>

namespace fs = std::filesystem;
using json = nlohmann::json;

namespace {

struct TempDir {
  fs::path path;
  TempDir() {
    std::string pattern = (fs::temp_directory_path() / "meowo-core-test-XXXXXX").string();
    char* result = mkdtemp(pattern.data());
    if (!result) throw std::runtime_error("mkdtemp failed");
    path = result;
  }
  ~TempDir() {
    std::error_code ec;
    fs::remove_all(path, ec);
  }
};

class Core {
 public:
  explicit Core(const fs::path& root) {
    char* error = nullptr;
    handle_ = meowo_workspace_open(root.string().c_str(), &error);
    if (!handle_) {
      const std::string message = error ? error : "unknown";
      meowo_free(error);
      throw std::runtime_error(message);
    }
  }
  ~Core() { meowo_workspace_close(handle_); }
  json call(const json& request) {
    const std::string text = request.dump();
    char* error = nullptr;
    char* result = meowo_invoke(handle_, text.c_str(), &error);
    if (!result) {
      const std::string message = error ? error : "unknown";
      meowo_free(error);
      throw std::runtime_error(message);
    }
    const std::string output(result);
    meowo_free(result);
    return json::parse(output);
  }

 private:
  uint64_t handle_ = 0;
};

}  // namespace

TEST(Core, CreatesListsOpensAndPersistsDocument) {
  TempDir temp;
  Core core(temp.path);
  const json created = core.call({{"op", "create_document"},
                                  {"title", "课堂笔记"},
                                  {"kind", "paged"},
                                  {"paper", {{"preset", "A4"}}}});
  EXPECT_EQ(created["title"], "课堂笔记");
  EXPECT_EQ(created["kind"], "paged");
  EXPECT_EQ(created["pages"].size(), 1u);
  const std::string id = created["id"];

  const json list = core.call({{"op", "list_documents"}});
  ASSERT_EQ(list["items"].size(), 1u);
  EXPECT_EQ(list["items"][0]["id"], id);

  json doc = core.call({{"op", "open_document"}, {"id", id}});
  doc["pages"][0]["layers"][0]["elements"].push_back(
      {{"id", "stroke_test"},
       {"type", "stroke"},
       {"color", "#112233"},
       {"width", 2.0},
       {"opacity", 1.0},
       {"highlighter", false},
       {"points", json::array({{10.0, 20.0, 0.5}, {30.0, 40.0, 0.8}})}});
  core.call({{"op", "save_document"}, {"document", doc}});

  const json reopened = core.call({{"op", "open_document"}, {"id", id}});
  ASSERT_EQ(reopened["pages"][0]["layers"][0]["elements"].size(), 1u);
  EXPECT_EQ(reopened["pages"][0]["layers"][0]["elements"][0]["id"], "stroke_test");
}

TEST(Core, FoldersFavoritesAndTrash) {
  TempDir temp;
  Core core(temp.path);
  const json folder = core.call({{"op", "create_folder"}, {"name", "课程"}});
  const std::string folder_id = folder["id"];
  const json doc = core.call({{"op", "create_document"},
                              {"title", "高数"},
                              {"kind", "paged"},
                              {"folderId", folder_id}});
  const std::string id = doc["id"];
  core.call({{"op", "toggle_favorite"}, {"id", id}});

  const json favorites = core.call({{"op", "list_documents"}, {"favorites", true}});
  ASSERT_EQ(favorites["items"].size(), 1u);
  EXPECT_TRUE(favorites["items"][0]["favorite"].get<bool>());

  core.call({{"op", "delete_document"}, {"id", id}});
  const json trash = core.call({{"op", "list_documents"}, {"trash", true}});
  ASSERT_EQ(trash["items"].size(), 1u);
  core.call({{"op", "restore_document"}, {"id", id}});
  const json active = core.call({{"op", "list_documents"}});
  EXPECT_EQ(active["items"].size(), 1u);
}

TEST(Core, MarkdownImportCreatesBodyText) {
  TempDir temp;
  Core core(temp.path);
  const fs::path markdown = temp.path / "note.md";
  {
    std::ofstream out(markdown);
    out << "# 标题\n\n这是一段 **Markdown**。\n";
  }
  const json result = core.call({{"op", "import_markdown"},
                                 {"sourcePath", markdown.string()}});
  const json doc = core.call({{"op", "open_document"}, {"id", result["id"]}});
  ASSERT_TRUE(doc["pages"][0]["body"].is_object());
  EXPECT_NE(doc["pages"][0]["body"]["markdown"].get<std::string>().find("Markdown"),
            std::string::npos);
}

TEST(Core, AssetRoundTrip) {
  TempDir temp;
  Core core(temp.path);
  const json doc = core.call({{"op", "create_document"},
                              {"title", "附件"},
                              {"kind", "paged"}});
  const std::string id = doc["id"];
  const json asset = core.call({{"op", "add_asset"},
                                {"documentId", id},
                                {"name", "hello.txt"},
                                {"mime", "text/plain"},
                                {"data", "aGVsbG8="}});
  EXPECT_EQ(asset["size"], 5);
  const json loaded = core.call({{"op", "get_asset"},
                                 {"documentId", id},
                                 {"assetId", asset["id"]}});
  EXPECT_EQ(loaded["base64"], "aGVsbG8=");
  const json reopened = core.call({{"op", "open_document"}, {"id", id}});
  ASSERT_EQ(reopened["assets"].size(), 1u);
  EXPECT_EQ(reopened["assets"][0]["name"], "hello.txt");
}

TEST(Core, SearchFindsTextAndTitle) {
  TempDir temp;
  Core core(temp.path);
  core.call({{"op", "create_document"}, {"title", "物理实验"}, {"kind", "paged"}});
  const json doc = core.call({{"op", "create_document"}, {"title", "其他"}, {"kind", "paged"}});
  json opened = core.call({{"op", "open_document"}, {"id", doc["id"]}});
  opened["pages"][0]["layers"][0]["elements"].push_back(
      {{"id", "txt"}, {"type", "text"}, {"markdown", "量子力学笔记"}});
  core.call({{"op", "save_document"}, {"document", opened}});
  const json found = core.call({{"op", "search"}, {"query", "量子"}});
  ASSERT_EQ(found["items"].size(), 1u);
  EXPECT_EQ(found["items"][0]["title"], "其他");
  const json by_title = core.call({{"op", "search"}, {"query", "物理"}});
  ASSERT_EQ(by_title["items"].size(), 1u);
}

TEST(Core, ExportsDocumentCopy) {
  TempDir temp;
  Core core(temp.path);
  const json doc = core.call({{"op", "create_document"}, {"title", "导出"}, {"kind", "paged"}});
  const fs::path target = temp.path / "copy.meowo";
  core.call({{"op", "export_document"},
             {"id", doc["id"]},
             {"targetPath", target.string()}});
  EXPECT_TRUE(fs::exists(target));
}

TEST(Core, RejectsConcurrentWorkspaceOpen) {
  TempDir temp;
  char* error = nullptr;
  const uint64_t first = meowo_workspace_open(temp.path.string().c_str(), &error);
  ASSERT_NE(first, 0u);
  meowo_free(error);
  error = nullptr;

  const uint64_t second = meowo_workspace_open(temp.path.string().c_str(), &error);
  EXPECT_EQ(second, 0u);
  ASSERT_NE(error, nullptr);
  EXPECT_NE(std::string(error).find("另一个"), std::string::npos);
  meowo_free(error);
  error = nullptr;

  meowo_workspace_close(first);
  const uint64_t third = meowo_workspace_open(temp.path.string().c_str(), &error);
  EXPECT_NE(third, 0u);
  meowo_free(error);
  if (third) meowo_workspace_close(third);
}
