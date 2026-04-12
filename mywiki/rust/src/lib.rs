// mywiki_ai - C-FFI library called from LuaJIT (LÖVE2D) via ffi.load.
//
// Exports a single workhorse:
//   char* mywiki_ai_node(const char* question, const char* node_id);
// which performs the chat + image API calls against xAI Grok, writes the
// generated illustration to assets/nodes/<id>.png, and returns a JSON string:
//   {"ok":true,"title":"...","body":"...","image":"assets/nodes/<id>.png"}
//   {"ok":false,"error":"..."}
//
// The caller must release the returned string via mywiki_ai_string_free.
//
// All blocking I/O happens on the calling thread, so the Lua side must invoke
// this from inside a love.thread worker — never the main loop.

use std::ffi::{CStr, CString};
use std::fs;
use std::io::{BufWriter, Read};
use std::os::raw::c_char;
use std::path::{Path, PathBuf};

use serde::Deserialize;
use serde_json::{json, Value};

use printpdf::{BuiltinFont, Mm, PdfDocument};

const CHAT_URL: &str = "https://api.x.ai/v1/responses";
const IMAGE_URL: &str = "https://api.x.ai/v1/images/generations";
const CHAT_MODEL: &str = "grok-4.20-reasoning";
const IMAGE_MODEL: &str = "grok-imagine-image";

#[derive(Deserialize, Default)]
struct NodeInfo {
    #[serde(default)]
    title: String,
    #[serde(default)]
    body: String,
}

fn err_json(msg: impl Into<String>) -> String {
    json!({ "ok": false, "error": msg.into() }).to_string()
}

fn ok_json(title: &str, body: &str, image: &str) -> String {
    json!({
        "ok": true,
        "title": title,
        "body": body,
        "image": image,
    })
    .to_string()
}

fn post_capturing(
    agent: &ureq::Agent,
    url: &str,
    api_key: &str,
    body: Value,
) -> Result<Value, String> {
    let resp = agent
        .post(url)
        .set("Authorization", &format!("Bearer {api_key}"))
        .set("Content-Type", "application/json")
        .send_json(body);
    match resp {
        Ok(r) => r.into_json().map_err(|e| format!("decode: {e}")),
        Err(ureq::Error::Status(code, r)) => {
            let body = r.into_string().unwrap_or_default();
            Err(format!("status {code}: {body}"))
        }
        Err(e) => Err(format!("transport: {e}")),
    }
}

fn fetch_text(
    agent: &ureq::Agent,
    api_key: &str,
    question: &str,
) -> Result<NodeInfo, String> {
    let sys_prompt = "You are an enthusiastic teacher building visual mindmap notes. \
        Given a question or topic, respond with ONLY a JSON object (no prose, no \
        code fences) with two keys: 'title' (max 6 words, no quotes) and 'body' \
        (markdown explainer, 4-8 short bullets or paragraphs, friendly tone, \
        concrete examples, no level-1 heading).";

    // xAI Responses API: POST /v1/responses with `input` array.
    let body = json!({
        "model": CHAT_MODEL,
        "input": [
            {"role": "system", "content": sys_prompt},
            {"role": "user",   "content": question},
        ],
    });

    let resp = post_capturing(agent, CHAT_URL, api_key, body)
        .map_err(|e| format!("chat {e}"))?;

    let content = extract_response_text(&resp)
        .ok_or_else(|| format!("chat: no message text in response: {resp}"))?;

    let cleaned = strip_code_fence(&content);
    if let Ok(info) = serde_json::from_str::<NodeInfo>(&cleaned) {
        return Ok(info);
    }
    Ok(NodeInfo {
        title: question.chars().take(48).collect(),
        body: content,
    })
}

/// Walk the Responses-API output array and pull the first
/// `type:"message"` element's `content[*].text` value.
fn extract_response_text(resp: &Value) -> Option<String> {
    let output = resp.get("output")?.as_array()?;
    for item in output {
        if item.get("type").and_then(|v| v.as_str()) == Some("message") {
            if let Some(content) = item.get("content").and_then(|v| v.as_array()) {
                for c in content {
                    if let Some(t) = c.get("text").and_then(|v| v.as_str()) {
                        return Some(t.trim().to_string());
                    }
                }
            }
        }
    }
    None
}

fn strip_code_fence(s: &str) -> String {
    let t = s.trim();
    if let Some(rest) = t.strip_prefix("```json").or_else(|| t.strip_prefix("```")) {
        if let Some(end) = rest.rfind("```") {
            return rest[..end].trim().to_string();
        }
    }
    t.to_string()
}

fn fetch_image(
    agent: &ureq::Agent,
    api_key: &str,
    title: &str,
    node_id: &str,
) -> Result<String, String> {
    let prompt = format!(
        "Vivid educational illustration about: {title}. Friendly, colorful, \
         premium digital concept art, soft cinematic lighting, no text, \
         no letters, centered composition."
    );

    let body = json!({
        "model": IMAGE_MODEL,
        "prompt": prompt,
        "n": 1,
        "response_format": "url",
    });

    let resp = post_capturing(agent, IMAGE_URL, api_key, body)
        .map_err(|e| format!("image {e}"))?;

    let url = resp
        .pointer("/data/0/url")
        .and_then(|v| v.as_str())
        .ok_or_else(|| "image: no url".to_string())?
        .to_string();

    let mut bytes: Vec<u8> = Vec::new();
    agent
        .get(&url)
        .call()
        .map_err(|e| format!("image fetch: {e}"))?
        .into_reader()
        .read_to_end(&mut bytes)
        .map_err(|e| format!("image read: {e}"))?;

    let dir = PathBuf::from("assets/nodes");
    fs::create_dir_all(&dir).map_err(|e| format!("mkdir: {e}"))?;
    let rel = format!("assets/nodes/{node_id}.png");
    fs::write(&rel, &bytes).map_err(|e| format!("write: {e}"))?;
    Ok(rel)
}

fn run_node(question: &str, node_id: &str) -> String {
    let api_key = match std::env::var("GROK_API_KEY") {
        Ok(k) if !k.is_empty() => k,
        _ => return err_json("GROK_API_KEY not set"),
    };

    let agent = ureq::AgentBuilder::new()
        .timeout(std::time::Duration::from_secs(180))
        .build();

    // Even on chat failure we degrade gracefully so the UI still gets a node.
    let info = fetch_text(&agent, &api_key, question).unwrap_or_else(|e| NodeInfo {
        title: question.chars().take(48).collect(),
        body: format!("_AI chat failed: {e}_"),
    });

    let title = if info.title.trim().is_empty() {
        "Untitled".to_string()
    } else {
        info.title.trim().to_string()
    };
    let body = info.body.trim().to_string();

    let image_rel = fetch_image(&agent, &api_key, &title, node_id).unwrap_or_default();
    ok_json(&title, &body, &image_rel)
}

// ---- export ----

#[derive(Deserialize)]
struct ExportNode {
    #[serde(default)]
    id: String,
    #[serde(default)]
    title: String,
    #[serde(default)]
    parent: String,
    #[serde(default)]
    body: String,
    #[serde(default)]
    image: String,
}

fn parse_nodes(json_str: &str) -> Result<Vec<ExportNode>, String> {
    serde_json::from_str::<Vec<ExportNode>>(json_str).map_err(|e| format!("parse: {e}"))
}

fn ensure_parent(path: &Path) -> Result<(), String> {
    if let Some(p) = path.parent() {
        fs::create_dir_all(p).map_err(|e| format!("mkdir: {e}"))?;
    }
    Ok(())
}

fn export_md(nodes: &[ExportNode], out: &Path) -> Result<(), String> {
    ensure_parent(out)?;
    let mut s = String::new();
    s.push_str("# MyWiki Export\n\n");
    for n in nodes {
        s.push_str(&format!("## {}\n\n", n.title));
        if !n.parent.is_empty() {
            s.push_str(&format!("_parent: {}_\n\n", n.parent));
        }
        if !n.image.is_empty() {
            s.push_str(&format!("![image]({})\n\n", n.image));
        }
        s.push_str(n.body.trim());
        s.push_str("\n\n---\n\n");
    }
    fs::write(out, s).map_err(|e| format!("write: {e}"))
}

fn csv_escape(s: &str) -> String {
    let needs = s.contains(',') || s.contains('"') || s.contains('\n');
    if needs {
        format!("\"{}\"", s.replace('"', "\"\""))
    } else {
        s.to_string()
    }
}

fn export_csv(nodes: &[ExportNode], out: &Path) -> Result<(), String> {
    ensure_parent(out)?;
    let mut s = String::from("id,parent,title,image,body\n");
    for n in nodes {
        s.push_str(&format!(
            "{},{},{},{},{}\n",
            csv_escape(&n.id),
            csv_escape(&n.parent),
            csv_escape(&n.title),
            csv_escape(&n.image),
            csv_escape(&n.body),
        ));
    }
    fs::write(out, s).map_err(|e| format!("write: {e}"))
}

fn export_jsonl(nodes: &[ExportNode], out: &Path) -> Result<(), String> {
    ensure_parent(out)?;
    let mut s = String::new();
    for n in nodes {
        let v = json!({
            "id": n.id,
            "parent": n.parent,
            "title": n.title,
            "image": n.image,
            "body": n.body,
        });
        s.push_str(&v.to_string());
        s.push('\n');
    }
    fs::write(out, s).map_err(|e| format!("write: {e}"))
}

fn export_pdf(nodes: &[ExportNode], out: &Path) -> Result<(), String> {
    ensure_parent(out)?;
    let (doc, page1, layer1) =
        PdfDocument::new("MyWiki Export", Mm(210.0), Mm(297.0), "Layer 1");
    let title_font = doc
        .add_builtin_font(BuiltinFont::HelveticaBold)
        .map_err(|e| format!("font: {e}"))?;
    let body_font = doc
        .add_builtin_font(BuiltinFont::Helvetica)
        .map_err(|e| format!("font: {e}"))?;

    let mut current = doc.get_page(page1).get_layer(layer1);
    let left = Mm(15.0);
    let top = Mm(280.0);
    let bottom = Mm(20.0);
    let mut y = top;
    let line = Mm(5.5);
    let title_line = Mm(7.5);

    let new_page = |doc: &printpdf::PdfDocumentReference| {
        let (p, l) = doc.add_page(Mm(210.0), Mm(297.0), "Layer");
        doc.get_page(p).get_layer(l)
    };

    fn wrap(s: &str, width: usize) -> Vec<String> {
        let mut out = Vec::new();
        for para in s.split('\n') {
            if para.is_empty() {
                out.push(String::new());
                continue;
            }
            let mut line = String::new();
            for word in para.split_whitespace() {
                if line.is_empty() {
                    line.push_str(word);
                } else if line.len() + 1 + word.len() <= width {
                    line.push(' ');
                    line.push_str(word);
                } else {
                    out.push(std::mem::take(&mut line));
                    line.push_str(word);
                }
            }
            if !line.is_empty() {
                out.push(line);
            }
        }
        out
    }

    for n in nodes {
        if y.0 < bottom.0 + 30.0 {
            current = new_page(&doc);
            y = top;
        }
        current.use_text(&n.title, 16.0, left, y, &title_font);
        y = Mm(y.0 - title_line.0);
        if !n.parent.is_empty() {
            current.use_text(format!("parent: {}", n.parent), 9.0, left, y, &body_font);
            y = Mm(y.0 - line.0);
        }
        for ln in wrap(&n.body, 95) {
            if y.0 < bottom.0 {
                current = new_page(&doc);
                y = top;
            }
            current.use_text(ln, 10.0, left, y, &body_font);
            y = Mm(y.0 - line.0);
        }
        y = Mm(y.0 - line.0);
    }

    let file = fs::File::create(out).map_err(|e| format!("create: {e}"))?;
    let mut buf = BufWriter::new(file);
    doc.save(&mut buf).map_err(|e| format!("pdf save: {e}"))?;
    Ok(())
}

fn run_export(format: &str, nodes_json: &str, out_path: &str) -> String {
    let nodes = match parse_nodes(nodes_json) {
        Ok(n) => n,
        Err(e) => return err_json(e),
    };
    let out = PathBuf::from(out_path);
    let res = match format.to_ascii_lowercase().as_str() {
        "md" | "markdown" => export_md(&nodes, &out),
        "csv" => export_csv(&nodes, &out),
        "jsonl" => export_jsonl(&nodes, &out),
        "pdf" => export_pdf(&nodes, &out),
        other => Err(format!("unknown format: {other}")),
    };
    match res {
        Ok(()) => json!({"ok": true, "path": out_path, "count": nodes.len()}).to_string(),
        Err(e) => err_json(e),
    }
}

// ---- C FFI surface ----

/// Generate a wiki node (title, body, image) for the given question.
///
/// # Safety
/// Both pointers must be valid, non-null, NUL-terminated UTF-8 C strings.
/// The returned string must be freed by `mywiki_ai_string_free`.
#[no_mangle]
pub unsafe extern "C" fn mywiki_ai_node(
    question: *const c_char,
    node_id: *const c_char,
) -> *mut c_char {
    let result = std::panic::catch_unwind(|| {
        if question.is_null() || node_id.is_null() {
            return err_json("null pointer");
        }
        let q = match CStr::from_ptr(question).to_str() {
            Ok(s) => s,
            Err(_) => return err_json("question not utf-8"),
        };
        let id = match CStr::from_ptr(node_id).to_str() {
            Ok(s) => s,
            Err(_) => return err_json("node_id not utf-8"),
        };
        run_node(q, id)
    })
    .unwrap_or_else(|_| err_json("rust panic"));

    CString::new(result)
        .unwrap_or_else(|_| CString::new("{\"ok\":false,\"error\":\"nul in result\"}").unwrap())
        .into_raw()
}

/// Free a string previously returned from this library.
///
/// # Safety
/// `ptr` must have been returned by `mywiki_ai_node` and not yet freed.
#[no_mangle]
pub unsafe extern "C" fn mywiki_ai_string_free(ptr: *mut c_char) {
    if !ptr.is_null() {
        let _ = CString::from_raw(ptr);
    }
}

/// Library version probe — handy for verifying ffi.load worked.
#[no_mangle]
pub extern "C" fn mywiki_ai_version() -> *const c_char {
    static VERSION: &[u8] = b"0.1.0\0";
    VERSION.as_ptr() as *const c_char
}

/// Export a list of nodes (JSON array) to disk in the requested format.
///
/// # Safety
/// All three pointers must be valid, non-null, NUL-terminated UTF-8 C strings.
/// Returned string must be freed with `mywiki_ai_string_free`.
#[no_mangle]
pub unsafe extern "C" fn mywiki_export(
    format: *const c_char,
    nodes_json: *const c_char,
    out_path: *const c_char,
) -> *mut c_char {
    let result = std::panic::catch_unwind(|| {
        if format.is_null() || nodes_json.is_null() || out_path.is_null() {
            return err_json("null pointer");
        }
        let f = match CStr::from_ptr(format).to_str() {
            Ok(s) => s,
            Err(_) => return err_json("format not utf-8"),
        };
        let j = match CStr::from_ptr(nodes_json).to_str() {
            Ok(s) => s,
            Err(_) => return err_json("nodes_json not utf-8"),
        };
        let o = match CStr::from_ptr(out_path).to_str() {
            Ok(s) => s,
            Err(_) => return err_json("out_path not utf-8"),
        };
        run_export(f, j, o)
    })
    .unwrap_or_else(|_| err_json("rust panic"));

    CString::new(result)
        .unwrap_or_else(|_| CString::new("{\"ok\":false,\"error\":\"nul in result\"}").unwrap())
        .into_raw()
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn err_json_is_well_formed() {
        let s = err_json("oops");
        let v: Value = serde_json::from_str(&s).unwrap();
        assert_eq!(v["ok"], false);
        assert_eq!(v["error"], "oops");
    }

    #[test]
    fn ok_json_carries_all_fields() {
        let s = ok_json("Hello", "Body text", "assets/nodes/abc.png");
        let v: Value = serde_json::from_str(&s).unwrap();
        assert_eq!(v["ok"], true);
        assert_eq!(v["title"], "Hello");
        assert_eq!(v["body"], "Body text");
        assert_eq!(v["image"], "assets/nodes/abc.png");
    }

    #[test]
    fn null_pointers_return_error_not_panic() {
        let raw = unsafe { mywiki_ai_node(std::ptr::null(), std::ptr::null()) };
        assert!(!raw.is_null());
        let s = unsafe { CStr::from_ptr(raw).to_str().unwrap().to_string() };
        unsafe { mywiki_ai_string_free(raw) };
        let v: Value = serde_json::from_str(&s).unwrap();
        assert_eq!(v["ok"], false);
        assert!(v["error"].as_str().unwrap().contains("null"));
    }

    #[test]
    fn version_string_is_non_empty() {
        let p = mywiki_ai_version();
        let s = unsafe { CStr::from_ptr(p).to_str().unwrap() };
        assert!(!s.is_empty());
    }

    #[test]
    fn extracts_text_from_responses_api_shape() {
        // Mirrors the real /v1/responses payload: an output array containing a
        // reasoning element followed by a message element with content[*].text.
        let resp = json!({
            "output": [
                {"type": "reasoning", "summary": [{"text": "thinking..."}]},
                {
                    "type": "message",
                    "role": "assistant",
                    "content": [
                        {"type": "output_text", "text": "{\"title\":\"Hi\",\"body\":\"yo\"}"}
                    ]
                }
            ]
        });
        let txt = extract_response_text(&resp).expect("text");
        assert_eq!(txt, "{\"title\":\"Hi\",\"body\":\"yo\"}");
        let info: NodeInfo = serde_json::from_str(&txt).unwrap();
        assert_eq!(info.title, "Hi");
        assert_eq!(info.body, "yo");
    }

    #[test]
    fn strip_fence_handles_json_block() {
        let s = "```json\n{\"title\":\"a\",\"body\":\"b\"}\n```";
        assert_eq!(strip_code_fence(s), "{\"title\":\"a\",\"body\":\"b\"}");
    }

    /// Live API check. Skipped unless GROK_API_KEY is set so CI without
    /// secrets stays green; run with:
    ///     GROK_API_KEY=... cargo test --release -- --ignored
    #[test]
    #[ignore]
    fn live_chat_returns_parseable_node() {
        let key = std::env::var("GROK_API_KEY").expect("GROK_API_KEY required");
        let agent = ureq::AgentBuilder::new()
            .timeout(std::time::Duration::from_secs(180))
            .build();
        let info = fetch_text(&agent, &key, "what is rust lang?").expect("fetch_text");
        eprintln!("title: {}", info.title);
        eprintln!("body : {}", info.body);
        assert!(!info.title.is_empty());
        assert!(!info.body.is_empty());
    }
}
