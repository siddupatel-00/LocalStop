use serde::Serialize;
use std::collections::HashSet;
use std::process::Command;

#[derive(Serialize, Clone)]
pub struct Server {
    pub pid: u32,
    pub port: u16,
    pub command: String,
    pub address: String,
}

const IGNORED: &[&str] = &[
    "controlcenter",
    "rapportd",
    "sharingd",
    "nearbyd",
    "identityservicesd",
    "airplayuiagent",
    "wifiagent",
    "cloudd",
    "code helper",
    "cursor helper",
    "opencode",
    "opencode helper",
    "localstop",
    "system",
    "idle",
    "svchost",
    "services",
    "lsass",
    "wininit",
    "csrss",
    "smss",
    "spoolsv",
    "dwm",
    "explorer",
    "searchhost",
    "searchindexer",
    "runtimebroker",
    "sihost",
    "taskhostw",
];

fn ignored(command: &str) -> bool {
    let name = command.trim().trim_end_matches(".exe").to_ascii_lowercase();
    IGNORED.contains(&name.as_str()) || name.contains("code helper")
}

fn normalize_address(address: &str) -> String {
    let host = address
        .strip_prefix('[')
        .and_then(|rest| rest.strip_suffix(']'))
        .unwrap_or(address);

    if host.is_empty()
        || host == "*"
        || host == "0.0.0.0"
        || host == "::"
        || host == "::1"
        || host == "127.0.0.1"
        || host == "localhost"
    {
        "localhost".into()
    } else {
        host.into()
    }
}

#[cfg(any(target_os = "macos", target_os = "linux"))]
fn port_from(address: &str) -> Option<u16> {
    address.rsplit(':').next()?.parse().ok()
}

fn cleanup(mut servers: Vec<Server>) -> Vec<Server> {
    let self_pid = std::process::id();
    let mut seen = HashSet::new();
    servers.retain(|server| {
        server.pid > 1
            && server.pid != self_pid
            && !server.command.to_ascii_lowercase().contains("localstop")
            && !ignored(&server.command)
            && seen.insert((server.pid, server.port))
    });
    servers.sort_by(|a, b| a.port.cmp(&b.port).then(a.pid.cmp(&b.pid)));
    servers
}

#[cfg(target_os = "macos")]
fn lsof_path() -> &'static str {
    "/usr/sbin/lsof"
}

#[cfg(target_os = "linux")]
fn lsof_path() -> &'static str {
    "lsof"
}

#[cfg(any(target_os = "macos", target_os = "linux"))]
fn scan_lsof() -> Vec<Server> {
    let uid = unsafe { libc::getuid() }.to_string();
    let output = Command::new(lsof_path())
        .args(["-nP", "-a", "+c", "0", "-iTCP", "-sTCP:LISTEN", "-u"])
        .arg(uid)
        .arg("-Fpcn")
        .output();

    let Ok(output) = output else {
        return Vec::new();
    };

    if !output.status.success() && output.stdout.is_empty() {
        return Vec::new();
    }

    let text = String::from_utf8_lossy(&output.stdout);
    let mut servers = Vec::new();
    let mut pid = 0u32;
    let mut command = String::new();

    for line in text.lines() {
        let mut chars = line.chars();
        let Some(field) = chars.next() else { continue };
        let value = chars.as_str();

        match field {
            'p' => {
                pid = value.parse().unwrap_or(0);
                command.clear();
            }
            'c' => command = value.to_string(),
            'n' => {
                let Some(port) = port_from(value) else { continue };
                let host = value.rsplit_once(':').map(|(host, _)| host).unwrap_or(value);
                servers.push(Server {
                    pid,
                    port,
                    command: command.clone(),
                    address: normalize_address(host),
                });
            }
            _ => {}
        }
    }

    cleanup(servers)
}

#[cfg(target_os = "linux")]
fn scan_ss() -> Option<Vec<Server>> {
    let output = Command::new("ss").args(["-ltnpH"]).output().ok()?;
    if !output.status.success() {
        return None;
    }

    let text = String::from_utf8_lossy(&output.stdout);
    let mut records: Vec<String> = Vec::new();
    for line in text.lines() {
        let trimmed = line.trim();
        if trimmed.starts_with("users:(") {
            if let Some(last) = records.last_mut() {
                last.push(' ');
                last.push_str(trimmed);
            }
        } else if !trimmed.is_empty() {
            records.push(trimmed.to_string());
        }
    }

    let mut servers = Vec::new();
    for record in records {
        let fields: Vec<&str> = record.split_whitespace().collect();
        if fields.len() < 6 {
            continue;
        }

        let Some(port) = port_from(fields[3]) else { continue };
        let host = fields[3]
            .rsplit_once(':')
            .map(|(host, _)| host)
            .unwrap_or(fields[3]);

        let process = fields[5..].join(" ");
        let Some(pid) = process
            .split(",pid=")
            .nth(1)
            .and_then(|rest| rest.split([',', ')']).next())
            .and_then(|pid| pid.parse::<u32>().ok())
        else {
            continue;
        };

        let command = process
            .split("((\"")
            .nth(1)
            .and_then(|rest| rest.split('"').next())
            .unwrap_or("unknown")
            .to_string();

        servers.push(Server {
            pid,
            port,
            command,
            address: normalize_address(host),
        });
    }

    Some(cleanup(servers))
}

#[cfg(target_os = "windows")]
fn scan_windows() -> Vec<Server> {
    use std::os::windows::process::CommandExt;

    const CREATE_NO_WINDOW: u32 = 0x0800_0000;

    let script = r#"[Console]::OutputEncoding=[System.Text.UTF8Encoding]::new($false); $procs=@{}; Get-Process -ErrorAction SilentlyContinue | ForEach-Object { $procs[[int64]$_.Id]=$_.ProcessName }; Get-NetTCPConnection -State Listen -ErrorAction SilentlyContinue | ForEach-Object { [pscustomobject]@{ port=[int]$_.LocalPort; pid=[int64]$_.OwningProcess; name=[string]$procs[[int64]$_.OwningProcess]; addr=[string]$_.LocalAddress } } | ConvertTo-Json -Compress"#;

    let output = Command::new("powershell")
        .args(["-NoProfile", "-NonInteractive", "-Command", script])
        .creation_flags(CREATE_NO_WINDOW)
        .output();

    let Ok(output) = output else {
        return Vec::new();
    };

    let text = String::from_utf8_lossy(&output.stdout);
    let value: serde_json::Value =
        serde_json::from_str(text.trim_start_matches('\u{feff}')).unwrap_or(serde_json::Value::Null);

    let items = match value {
        serde_json::Value::Array(items) => items,
        serde_json::Value::Object(_) => vec![value],
        _ => Vec::new(),
    };

    let mut servers = Vec::new();
    for item in items {
        let Some(port) = item.get("port").and_then(|v| v.as_u64()) else { continue };
        let Some(pid) = item.get("pid").and_then(|v| v.as_u64()) else { continue };
        let Ok(port) = u16::try_from(port) else { continue };
        let Ok(pid) = u32::try_from(pid) else { continue };
        let command = item
            .get("name")
            .and_then(|v| v.as_str())
            .filter(|name| !name.is_empty())
            .unwrap_or("unknown")
            .to_string();
        let address = item.get("addr").and_then(|v| v.as_str()).unwrap_or("localhost");

        servers.push(Server {
            pid,
            port,
            command,
            address: normalize_address(address),
        });
    }

    cleanup(servers)
}

pub fn scan() -> Vec<Server> {
    #[cfg(target_os = "macos")]
    {
        scan_lsof()
    }
    #[cfg(target_os = "linux")]
    {
        scan_ss().unwrap_or_else(scan_lsof)
    }
    #[cfg(target_os = "windows")]
    {
        scan_windows()
    }
}

#[cfg(unix)]
pub fn stop(pid: u32) -> Result<(), String> {
    if pid <= 1 || pid == std::process::id() {
        return Err("Invalid process".into());
    }

    let Ok(target) = i32::try_from(pid) else {
        return Err("Invalid process".into());
    };
    let rc = unsafe { libc::kill(target, libc::SIGTERM) };
    if rc != 0 {
        let error = std::io::Error::last_os_error();
        if error.raw_os_error() == Some(libc::ESRCH) {
            return Ok(());
        }
        return Err(error.to_string());
    }

    let mut alive = true;
    for _ in 0..10 {
        std::thread::sleep(std::time::Duration::from_millis(200));
        let rc = unsafe { libc::kill(target, 0) };
        if rc != 0 {
            let error = std::io::Error::last_os_error();
            if error.raw_os_error() == Some(libc::ESRCH) {
                alive = false;
                break;
            }
        }
    }

    if !alive {
        return Ok(());
    }

    unsafe {
        libc::kill(target, libc::SIGKILL);
    }
    std::thread::sleep(std::time::Duration::from_millis(200));

    let rc = unsafe { libc::kill(target, 0) };
    if rc != 0 {
        let error = std::io::Error::last_os_error();
        if error.raw_os_error() == Some(libc::ESRCH) {
            return Ok(());
        }
        return Err(error.to_string());
    }

    Err("Process did not stop".into())
}

#[cfg(windows)]
pub fn stop(pid: u32) -> Result<(), String> {
    use std::os::windows::process::CommandExt;

    if pid <= 1 || pid == std::process::id() {
        return Err("Invalid process".into());
    }

    const CREATE_NO_WINDOW: u32 = 0x0800_0000;

    let output = Command::new("taskkill")
        .args(["/PID", &pid.to_string(), "/T", "/F"])
        .creation_flags(CREATE_NO_WINDOW)
        .output()
        .map_err(|error| error.to_string())?;

    if output.status.success() || output.status.code() == Some(128) {
        return Ok(());
    }

    let message = String::from_utf8_lossy(&output.stderr).trim().to_string();
    Err(if message.is_empty() {
        "Could not stop process".into()
    } else {
        message
    })
}

fn is_local_url(url: &str) -> bool {
    let rest = url
        .strip_prefix("http://localhost:")
        .or_else(|| url.strip_prefix("http://127.0.0.1:"));

    let Some(port) = rest else {
        return false;
    };

    !port.is_empty()
        && port.bytes().all(|byte| byte.is_ascii_digit())
        && port.parse::<u16>().map(|port| port > 0).unwrap_or(false)
}

#[cfg(any(target_os = "macos", target_os = "linux"))]
fn spawn_and_reap(child: std::process::Child) {
    std::thread::spawn(move || {
        let mut child = child;
        let _ = child.wait();
    });
}

#[cfg(any(target_os = "macos", target_os = "linux"))]
pub fn open_url(url: &str) -> Result<(), String> {
    if !is_local_url(url) {
        return Err("Only localhost URLs are allowed".into());
    }

    #[cfg(target_os = "macos")]
    let child = Command::new("open").arg(url).spawn();

    #[cfg(target_os = "linux")]
    let child = Command::new("xdg-open").arg(url).spawn();

    let child = child.map_err(|error| error.to_string())?;
    spawn_and_reap(child);
    Ok(())
}

#[cfg(windows)]
pub fn open_url(url: &str) -> Result<(), String> {
    use std::os::windows::process::CommandExt;

    if !is_local_url(url) {
        return Err("Only localhost URLs are allowed".into());
    }

    const CREATE_NO_WINDOW: u32 = 0x0800_0000;

    Command::new("cmd")
        .args(["/C", "start", "", url])
        .creation_flags(CREATE_NO_WINDOW)
        .spawn()
        .map(|child| {
            std::thread::spawn(move || {
                let mut child = child;
                let _ = child.wait();
            });
        })
        .map_err(|error| error.to_string())
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn normalizes_wildcard_and_loopback_addresses() {
        for address in ["", "*", "0.0.0.0", "::", "[::]", "::1", "[::1]", "127.0.0.1", "localhost"] {
            assert_eq!(normalize_address(address), "localhost");
        }
        assert_eq!(normalize_address("192.168.1.10"), "192.168.1.10");
    }

    #[test]
    fn only_accepts_plain_localhost_urls() {
        assert!(is_local_url("http://localhost:3000"));
        assert!(is_local_url("http://127.0.0.1:8080"));
        assert!(!is_local_url("http://localhost:0"));
        assert!(!is_local_url("http://localhost:+80"));
        assert!(!is_local_url("https://localhost:3000"));
        assert!(!is_local_url("http://localhost:3000/path"));
        assert!(!is_local_url("http://example.com:3000"));
        assert!(!is_local_url("file:///etc/passwd"));
    }
}
