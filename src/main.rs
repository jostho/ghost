use std::str;
use std::thread;
use std::time::Duration;
use warp::Filter;
use http::Response;
use clap::{App, Arg};
use rand::{thread_rng, Rng};
use rand::distributions::Alphanumeric;
use bytes;

const ARG_PORT: &str = "port";
const ARG_LOCAL: &str = "local";
const HEADER_INPUT: &str = "X-Ghost-Input";
const HEADER_CONTENT_TYPE: &str = "Content-Type";
const CONTENT_LENGTH_LIMIT: u64 = 1024 * 64;

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
            .default_value("8080")
        )
        .arg(
            Arg::with_name(ARG_LOCAL)
            .long(ARG_LOCAL)
            .help("bind on local interface")
            .takes_value(false)
        )
        .get_matches();

    // decide port
    let port = args.value_of(ARG_PORT).unwrap();
    let port = port.parse().unwrap_or(8080);

    // decide interface
    let mut interface = [0, 0, 0, 0]; // default
    if args.is_present(ARG_LOCAL) {
        interface = [127, 0, 0, 1];
    }

    // GET /healthcheck
    let healthcheck = warp::path("healthcheck")
        .and(warp::get())
        .map(|| "Ok");

    // GET /version
    let version = warp::path("version")
        .and(warp::get())
        .map(|| clap::crate_version!());

    // GET /api/status/:u16
    let api_status = warp::path!("api" / "status" / u16)
        .and(warp::get())
        .map(|code: u16| {
            let mut response_code = 200;
            if code > 200 && code < 600 {
                response_code = code;
            }
            Response::builder()
                .status(response_code)
                .header(HEADER_INPUT, code.to_string())
                .body(format!("status: {}", response_code))
        });

    // GET /api/bytes/:u16
    let api_bytes = warp::path!("api" / "bytes" / u16)
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
    let api_sleep = warp::path!("api" / "sleep" / u16)
        .and(warp::get())
        .map(|millis: u16| {
            thread::sleep(Duration::from_millis(millis as u64));
            Response::builder()
                .header(HEADER_INPUT, millis.to_string())
                .body(format!("millis: {}", millis))
        });

    // POST /api/post
    let api_post = warp::path!("api" / "post")
        .and(warp::post())
        .and(warp::header::<String>(HEADER_CONTENT_TYPE))
        .and(warp::body::content_length_limit(CONTENT_LENGTH_LIMIT))
        .and(warp::body::bytes())
        .map(|content_type: String, bytes: bytes::Bytes| {
            Response::builder()
                .header(HEADER_CONTENT_TYPE, content_type)
                .body(format!("{}", str::from_utf8(&bytes).unwrap_or("")))
        });

    let routes = healthcheck.or(version)
        .or(api_status).or(api_bytes).or(api_sleep)
        .or(api_post)
        .with(warp::log(clap::crate_name!()));
    warp::serve(routes).run((interface, port)).await;
}
