use bytes::Bytes;
use clap::{App, Arg};
use http::Response;
use rand::distributions::Alphanumeric;
use rand::{thread_rng, Rng};
use std::str;
use std::thread;
use std::time::Duration;
use warp::Filter;

const ARG_PORT: &str = "port";
const ARG_LOCAL: &str = "local";
const HEADER_INPUT: &str = "X-Ghost-Input";
const HEADER_CONTENT_TYPE: &str = "Content-Type";
const CONTENT_LENGTH_LIMIT: u64 = 1024 * 64;
const MAX_PORT: u16 = 32768;

#[tokio::main]
async fn main() {
    pretty_env_logger::init();

    let args = App::new(clap::crate_name!())
        .about(clap::crate_description!())
        .version(clap::crate_version!())
        .arg(
            Arg::with_name(ARG_PORT)
                .long(ARG_PORT)
                .help("Port number to use")
                .default_value("8000")
                .validator(is_valid_port),
        )
        .arg(
            Arg::with_name(ARG_LOCAL)
                .long(ARG_LOCAL)
                .help("Bind on local interface")
                .takes_value(false),
        )
        .get_matches();

    // decide port
    let port = args.value_of(ARG_PORT).unwrap();
    let port = port.parse().unwrap();

    // decide interface
    let interface = if args.is_present(ARG_LOCAL) {
        [127, 0, 0, 1]
    } else {
        [0, 0, 0, 0] // default
    };

    // GET /healthcheck
    let healthcheck = warp::path("healthcheck").and(warp::get()).map(|| "Ok");

    // GET /version
    let version = warp::path("version")
        .and(warp::get())
        .map(|| clap::crate_version!());

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
        .map(|content_type: String, bytes: Bytes| {
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
    let routes = healthcheck
        .or(version)
        .or(api)
        .with(warp::log(clap::crate_name!()));
    warp::serve(routes).run((interface, port)).await;
}

fn is_valid_port(val: String) -> Result<(), String> {
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
        let result = is_valid_port("str".to_string());
        assert!(result.is_err());
        assert_eq!(result.unwrap_err(), "invalid digit found in string");
    }

    #[test]
    fn is_valid_port_for_8000() {
        let result = is_valid_port("8000".to_string());
        assert!(result.is_ok());
        assert_eq!(result.unwrap(), ());
    }

    #[test]
    fn is_valid_port_for_32768() {
        let result = is_valid_port("32768".to_string());
        assert!(result.is_err());
        assert_eq!(
            result.unwrap_err(),
            format!("value should be less than {}", MAX_PORT)
        );
    }
}
