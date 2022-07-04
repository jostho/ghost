use chrono::Local;
use clap::Parser;
use http::Response;
use rand::distributions::Alphanumeric;
use rand::{thread_rng, Rng};
use std::env;
use std::str;
use std::thread;
use std::time::Duration;
use warp::{reply::Reply, Filter};

const HEADER_INPUT: &str = "X-Ghost-Input";
const HEADER_CONTENT_TYPE: &str = "Content-Type";
const CONTENT_LENGTH_LIMIT: u64 = 1024 * 64;
const MAX_PORT: u16 = 32768;

const ENV_RELEASE_FILE: &str = "GHOST_RELEASE";
const DEFAULT_RELEASE_FILE: &str = "/usr/local/etc/ghost-release";
const ENV_STATIC_DIR: &str = "GHOST_STATIC_DIR";
const DEFAULT_STATIC_DIR: &str = "static";

/// Read cli args
#[derive(Parser, Debug)]
#[clap(version, about)]
struct Args {
    /// Port number to use
    #[clap(short, long, value_parser, default_value_t = 8000, validator = is_valid_port)]
    port: u16,

    /// Static dir
    #[clap(short, long, value_parser, env = ENV_STATIC_DIR, default_value = DEFAULT_STATIC_DIR)]
    static_dir: String,

    /// Bind on local interface
    #[clap(short, long)]
    local: bool,
}

#[tokio::main]
async fn main() {
    pretty_env_logger::init();
    let args = Args::parse();

    // decide interface
    let interface = if args.local {
        [127, 0, 0, 1]
    } else {
        [0, 0, 0, 0] // default
    };

    // GET /healthcheck
    let healthcheck = warp::path("healthcheck").and(warp::get()).map(|| "Ok");

    // GET /version
    let version = warp::path("version")
        .and(warp::get())
        .map(|| env!("CARGO_PKG_VERSION") );

    // GET /release
    let release_file = match env::var(ENV_RELEASE_FILE) {
        Ok(val) => val,
        Err(_e) => DEFAULT_RELEASE_FILE.to_string(),
    };
    let release = warp::path("release")
        .and(warp::get())
        .and(warp::fs::file(release_file))
        .map(|reply: warp::fs::File| {
            warp::reply::with_header(reply, HEADER_CONTENT_TYPE, "text/plain").into_response()
        });

    // GET /static
    let static_root = warp::path("static").and(warp::fs::dir(args.static_dir.to_string()));

    // GET /api
    let api_root = warp::path!("api" / ..);
    let api_help = warp::get()
        .and(warp::path::end())
        .map(|| "Welcome to the API");

    // GET /api/status/:u16
    let api_status = warp::path!("status" / u16)
        .and(warp::get())
        .map(|code: u16| {
            let response_code = if code > 200 && code < 600 { code } else { 200 };
            Response::builder()
                .status(response_code)
                .header(HEADER_INPUT, code.to_string())
                .body(format!("status: {}", response_code))
        });

    // GET /api/bytes/:u16
    let api_bytes = warp::path!("bytes" / u16)
        .and(warp::get())
        .map(|num_bytes: u16| {
            let rand_string: String = thread_rng()
                .sample_iter(&Alphanumeric)
                .take(num_bytes as usize)
                .map(char::from)
                .collect();
            Response::builder()
                .header(HEADER_INPUT, num_bytes.to_string())
                .body(rand_string)
        });

    // GET /api/sleep/:u16
    let api_sleep = warp::path!("sleep" / u16)
        .and(warp::get())
        .map(|millis: u16| {
            thread::sleep(Duration::from_millis(millis as u64));
            Response::builder()
                .header(HEADER_INPUT, millis.to_string())
                .body(format!("millis: {}", millis))
        });

    // POST /api/post
    let api_post = warp::path!("post")
        .and(warp::post())
        .and(warp::header::<String>(HEADER_CONTENT_TYPE))
        .and(warp::body::content_length_limit(CONTENT_LENGTH_LIMIT))
        .and(warp::body::bytes())
        .map(|content_type: String, bytes: warp::hyper::body::Bytes| {
            Response::builder()
                .header(HEADER_CONTENT_TYPE, content_type)
                .body(str::from_utf8(&bytes).unwrap_or("").to_string())
        });

    let api = api_root.and(
        api_help
            .or(api_status)
            .or(api_bytes)
            .or(api_sleep)
            .or(api_post),
    );
    let custom_log = warp::log::custom(|info| {
        println!(
            "{} - - {:?} \"{} {} {:?}\" {} \"{}\" \"{}\" \"{}\" {:?}",
            info.remote_addr().unwrap().ip(),
            Local::now(),
            info.method(),
            info.path(),
            info.version(),
            info.status().as_u16(),
            info.referer().unwrap_or("-"),
            info.user_agent().unwrap_or("-"),
            info.host().unwrap_or("-"),
            info.elapsed(),
        );
    });
    let routes = healthcheck
        .or(version)
        .or(release)
        .or(static_root)
        .or(api)
        .with(custom_log);
    warp::serve(routes).run((interface, args.port)).await;
}

fn is_valid_port(val: &str) -> Result<(), String> {
    let port: u16 = match val.parse() {
        Ok(port) => port,
        Err(e) => return Err(e.to_string()),
    };

    if port < MAX_PORT {
        Ok(())
    } else {
        Err(format!("value should be less than {}", MAX_PORT))
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn is_valid_port_for_string() {
        let result = is_valid_port("str");
        assert!(result.is_err());
        assert_eq!(result.unwrap_err(), "invalid digit found in string");
    }

    #[test]
    fn is_valid_port_for_8000() {
        let result = is_valid_port("8000");
        assert!(result.is_ok());
        assert_eq!(result.unwrap(), ());
    }

    #[test]
    fn is_valid_port_for_max_port() {
        let result = is_valid_port(&MAX_PORT.to_string());
        assert!(result.is_err());
        assert_eq!(
            result.unwrap_err(),
            format!("value should be less than {}", MAX_PORT)
        );
    }
}
