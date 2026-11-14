// The C side of Desk's window (deskshell.h): the vendored `webview` library compiled in, one binding each way, and
// the system's folder and file choosers on Windows and Linux. The Mac's chooser is in Swift (NSOpenPanel).
#define WEBVIEW_STATIC
#include "vendor/webview/webview.h"
#include "deskshell.h"

#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <string>

#if defined(_WIN32)
#include <shobjidl.h>
#include <shellapi.h>
#endif

struct deskshell {
  webview_t w = nullptr;
  deskshell_message_fn fn = nullptr;
  void *context = nullptr;
};

namespace {

// The page's side of the channel: `window.deckieShell.send(text)` to Swift, `onmessage` for what Swift sends.
// Messages that arrive before the page sets `onmessage` wait in a queue, so none is lost while the page loads.
const char *kInit = R"JS(
(function () {
  if (window.deckieShell) return;
  var queue = [];
  var handler = null;
  window.deckieShell = {
    engine: "%ENGINE%",
    send: function (text) { return window.__deckieShellSend(String(text)); },
    receive: function (text) { if (handler) handler(text); else queue.push(text); },
    set onmessage(fn) { handler = fn; var q = queue; queue = []; q.forEach(function (t) { fn(t); }); },
    get onmessage() { return handler; }
  };
})();
)JS";

// `text` as a JavaScript string literal: JSON's escapes, and the two line separators JavaScript did not always allow.
std::string js_string(const char *text) {
  std::string out = "\"";
  for (const unsigned char *p = reinterpret_cast<const unsigned char *>(text); *p; ++p) {
    unsigned char c = *p;
    switch (c) {
    case '"': out += "\\\""; break;
    case '\\': out += "\\\\"; break;
    case '\n': out += "\\n"; break;
    case '\r': out += "\\r"; break;
    case '\t': out += "\\t"; break;
    default:
      if (c < 0x20) {
        char buf[8];
        std::snprintf(buf, sizeof buf, "\\u%04x", c);
        out += buf;
      } else if (c == 0xE2 && p[1] == 0x80 && (p[2] == 0xA8 || p[2] == 0xA9)) {
        out += p[2] == 0xA8 ? "\\u2028" : "\\u2029";
        p += 2;
      } else {
        out += static_cast<char>(c);
      }
    }
  }
  out += "\"";
  return out;
}

// The page sent one message: its arguments arrive as a JSON array holding one string.
void on_send(const char *id, const char *req, void *arg) {
  auto *s = static_cast<deskshell *>(arg);
  if (s->fn) s->fn(req, s->context);
  webview_return(s->w, id, 0, "null");
}

struct posted {
  deskshell *s;
  std::string js;
};

void run_posted(webview_t w, void *arg) {
  auto *p = static_cast<posted *>(arg);
  webview_eval(w, p->js.c_str());
  delete p;
}

struct work {
  deskshell_work_fn fn;
  void *context;
};

void run_work(webview_t, void *arg) {
  auto *k = static_cast<work *>(arg);
  k->fn(k->context);
  delete k;
}

char *dup(const std::string &s) {
  char *out = static_cast<char *>(std::malloc(s.size() + 1));
  if (out) std::memcpy(out, s.c_str(), s.size() + 1);
  return out;
}

#if defined(_WIN32)
std::wstring widen(const char *s) {
  if (!s) return L"";
  int n = MultiByteToWideChar(CP_UTF8, 0, s, -1, nullptr, 0);
  std::wstring w(n > 0 ? n - 1 : 0, L'\0');
  if (n > 1) MultiByteToWideChar(CP_UTF8, 0, s, -1, &w[0], n);
  return w;
}

std::string narrow(const wchar_t *w) {
  int n = WideCharToMultiByte(CP_UTF8, 0, w, -1, nullptr, 0, nullptr, nullptr);
  std::string s(n > 0 ? n - 1 : 0, '\0');
  if (n > 1) WideCharToMultiByte(CP_UTF8, 0, w, -1, &s[0], n, nullptr, nullptr);
  return s;
}

// Folders dropped on the window, on Windows. The page cannot learn a dropped folder's path; WebView2 lets it hand the
// dropped items to the host (`chrome.webview.postMessageWithAdditionalObjects`), and this handler, beside the
// `webview` library's own, reads their paths and passes them on as one message, {"type":"shell.droppedPaths",...}.
class drop_handler : public ICoreWebView2WebMessageReceivedEventHandler {
public:
  explicit drop_handler(deskshell *s) : s_(s) {}
  HRESULT STDMETHODCALLTYPE QueryInterface(REFIID riid, void **out) override {
    if (riid == IID_IUnknown || riid == IID_ICoreWebView2WebMessageReceivedEventHandler) {
      *out = this;
      AddRef();
      return S_OK;
    }
    *out = nullptr;
    return E_NOINTERFACE;
  }
  ULONG STDMETHODCALLTYPE AddRef() override { return ++refs_; }
  ULONG STDMETHODCALLTYPE Release() override {
    ULONG r = --refs_;
    if (r == 0) delete this;
    return r;
  }
  HRESULT STDMETHODCALLTYPE Invoke(ICoreWebView2 *, ICoreWebView2WebMessageReceivedEventArgs *args) override {
    ICoreWebView2WebMessageReceivedEventArgs2 *args2 = nullptr;
    if (FAILED(args->QueryInterface(IID_ICoreWebView2WebMessageReceivedEventArgs2, reinterpret_cast<void **>(&args2))) || !args2) {
      return S_OK;
    }
    ICoreWebView2ObjectCollectionView *objects = nullptr;
    std::string json = "{\"type\":\"shell.droppedPaths\",\"paths\":[";
    int added = 0;
    if (SUCCEEDED(args2->get_AdditionalObjects(&objects)) && objects) {
      UINT32 count = 0;
      objects->get_Count(&count);
      for (UINT32 i = 0; i < count; ++i) {
        IUnknown *item = nullptr;
        if (FAILED(objects->GetValueAtIndex(i, &item)) || !item) continue;
        ICoreWebView2File *file = nullptr;
        if (SUCCEEDED(item->QueryInterface(IID_ICoreWebView2File, reinterpret_cast<void **>(&file))) && file) {
          LPWSTR path = nullptr;
          if (SUCCEEDED(file->get_Path(&path)) && path) {
            if (added++) json += ",";
            json += js_string(narrow(path).c_str());
            CoTaskMemFree(path);
          }
          file->Release();
        }
        item->Release();
      }
      objects->Release();
    }
    args2->Release();
    json += "]}";
    if (added && s_->fn) {
      std::string wrapped = "[" + js_string(json.c_str()) + "]";
      s_->fn(wrapped.c_str(), s_->context);
    }
    return S_OK;
  }

private:
  deskshell *s_;
  ULONG refs_ = 1;
};

void listen_for_drops(deskshell *s) {
  auto *controller = static_cast<ICoreWebView2Controller *>(
      webview_get_native_handle(s->w, WEBVIEW_NATIVE_HANDLE_KIND_BROWSER_CONTROLLER));
  if (!controller) return;
  ICoreWebView2 *view = nullptr;
  if (FAILED(controller->get_CoreWebView2(&view)) || !view) return;
  auto *handler = new drop_handler(s);
  EventRegistrationToken token;
  view->add_WebMessageReceived(handler, &token);
  handler->Release();
  view->Release();
}

char *choose(deskshell *s, const char *title, bool folders) {
  IFileOpenDialog *dialog = nullptr;
  if (FAILED(CoCreateInstance(CLSID_FileOpenDialog, nullptr, CLSCTX_INPROC_SERVER, IID_PPV_ARGS(&dialog)))) {
    return nullptr;
  }
  DWORD options = 0;
  dialog->GetOptions(&options);
  options |= FOS_FORCEFILESYSTEM | FOS_PATHMUSTEXIST;
  if (folders) options |= FOS_PICKFOLDERS; else options |= FOS_FILEMUSTEXIST;
  dialog->SetOptions(options);
  std::wstring t = widen(title);
  dialog->SetTitle(t.c_str());
  char *out = nullptr;
  HWND owner = s ? static_cast<HWND>(webview_get_window(s->w)) : nullptr;
  if (SUCCEEDED(dialog->Show(owner))) {
    IShellItem *item = nullptr;
    if (SUCCEEDED(dialog->GetResult(&item))) {
      PWSTR path = nullptr;
      if (SUCCEEDED(item->GetDisplayName(SIGDN_FILESYSPATH, &path))) {
        out = dup(narrow(path));
        CoTaskMemFree(path);
      }
      item->Release();
    }
  }
  dialog->Release();
  return out;
}
#elif defined(WEBVIEW_GTK)
char *choose(deskshell *s, const char *title, bool folders) {
  GtkWindow *owner = s ? static_cast<GtkWindow *>(webview_get_window(s->w)) : nullptr;
#if GTK_MAJOR_VERSION >= 4
  (void)owner; (void)title; (void)folders;
  return nullptr; // GTK 4 has no blocking dialog; this build uses GTK 3 (webkit2gtk-4.1).
#else
  GtkWidget *dialog = gtk_file_chooser_dialog_new(
      title, owner, folders ? GTK_FILE_CHOOSER_ACTION_SELECT_FOLDER : GTK_FILE_CHOOSER_ACTION_OPEN, "_Cancel",
      GTK_RESPONSE_CANCEL, folders ? "_Choose" : "_Open", GTK_RESPONSE_ACCEPT, nullptr);
  char *out = nullptr;
  if (gtk_dialog_run(GTK_DIALOG(dialog)) == GTK_RESPONSE_ACCEPT) {
    char *path = gtk_file_chooser_get_filename(GTK_FILE_CHOOSER(dialog));
    if (path) {
      out = dup(path);
      g_free(path);
    }
  }
  gtk_widget_destroy(dialog);
  return out;
#endif
}
#else
char *choose(deskshell *, const char *, bool) { return nullptr; }
#endif

} // namespace

extern "C" {

deskshell_t deskshell_create(int debug, const char *title, int width, int height) {
  webview_t w = webview_create(debug, nullptr);
  if (!w) return nullptr;
  auto *s = new deskshell;
  s->w = w;
  webview_set_title(w, title);
  webview_set_size(w, width, height, WEBVIEW_HINT_NONE);
  std::string init = kInit;
  std::string marker = "%ENGINE%";
  init.replace(init.find(marker), marker.size(), deskshell_engine_name());
  webview_init(w, init.c_str());
  webview_bind(w, "__deckieShellSend", on_send, s);
#if defined(_WIN32)
  listen_for_drops(s);
#endif
  return s;
}

void deskshell_on_message(deskshell_t s, deskshell_message_fn fn, void *context) {
  s->fn = fn;
  s->context = context;
}

void deskshell_load(deskshell_t s, const char *url) { webview_navigate(s->w, url); }

void deskshell_set_html(deskshell_t s, const char *html) { webview_set_html(s->w, html); }

void deskshell_post(deskshell_t s, const char *text) {
  auto *p = new posted{s, "window.deckieShell && window.deckieShell.receive(" + js_string(text) + ");"};
  webview_dispatch(s->w, run_posted, p);
}

void deskshell_eval(deskshell_t s, const char *js) { webview_eval(s->w, js); }

void deskshell_dispatch(deskshell_t s, deskshell_work_fn fn, void *context) {
  webview_dispatch(s->w, run_work, new work{fn, context});
}

int deskshell_run(deskshell_t s) { return webview_run(s->w) == WEBVIEW_ERROR_OK ? 0 : 1; }

void deskshell_terminate(deskshell_t s) { webview_terminate(s->w); }

void deskshell_destroy(deskshell_t s) {
  if (!s) return;
  webview_destroy(s->w);
  delete s;
}

char *deskshell_choose_folder(deskshell_t s, const char *title) { return choose(s, title, true); }

char *deskshell_choose_file(deskshell_t s, const char *title) { return choose(s, title, false); }

void deskshell_open_folder(const char *path) {
#if defined(_WIN32)
  std::wstring p = widen(path);
  ShellExecuteW(nullptr, L"open", p.c_str(), nullptr, nullptr, SW_SHOWNORMAL);
#elif defined(WEBVIEW_GTK)
  GFile *f = g_file_new_for_path(path);
  char *uri = g_file_get_uri(f);
  g_app_info_launch_default_for_uri(uri, nullptr, nullptr);
  g_free(uri);
  g_object_unref(f);
#else
  (void)path;
#endif
}

void deskshell_free(char *text) { std::free(text); }

void *deskshell_native_view(deskshell_t s) {
#if defined(WEBVIEW_EDGE)
  return webview_get_native_handle(s->w, WEBVIEW_NATIVE_HANDLE_KIND_BROWSER_CONTROLLER);
#else
  return webview_get_native_handle(s->w, WEBVIEW_NATIVE_HANDLE_KIND_UI_WIDGET);
#endif
}

const char *deskshell_engine_name(void) {
#if defined(WEBVIEW_EDGE)
  return "WebView2";
#elif defined(WEBVIEW_GTK)
  return "WebKitGTK";
#else
  return "WKWebView";
#endif
}

} // extern "C"
