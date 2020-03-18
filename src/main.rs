use std::thread;
use std::time::Duration;
use warp::Filter;
use http::Response;
use clap::{App, Arg};
use rand::{thread_rng, Rng};
use rand::distributions::Alphanumeric;

const ARG_PORT: &str = "port";
const ARG_LOCAL: &str = "local";
const INPUT_HEADER: &str = "X-Ghost-Input";

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
    let healthcheck = warp::path("healthcheck").map(|| "Ok");

    // GET /version
    let version = warp::path("version").map(|| clap::crate_version!());

    // GET /api/status/:u16
    let api_status = warp::path!("api" / "status" / u16)
        .map(|code: u16| {
            let mut response_code = 200;
            if code > 200 && code < 600 {
                response_code = code;
            }
            Response::builder()
                .status(response_code)
                .header(INPUT_HEADER, code.to_string())
                .body(format!("status: {}", response_code))
        });

    // GET /api/bytes/:u16
    let api_bytes = warp::path!("api" / "bytes" / u16)
        .map(|num_bytes: u16| {
            let rand_string: String = thread_rng()
                .sample_iter(&Alphanumeric)
                .take(num_bytes as usize)
                .collect();
            Response::builder()
                .header(INPUT_HEADER, num_bytes.to_string())
                .body(rand_string)
        });

    // GET /api/sleep/:u16
    let api_sleep = warp::path!("api" / "sleep" / u16)
        .map(|millis: u16| {
            thread::sleep(Duration::from_millis(millis as u64));
            Response::builder()
                .header(INPUT_HEADER, millis.to_string())
                .body(format!("millis: {}", millis))
        });

    let routes = healthcheck.or(version)
        .or(api_status).or(api_bytes).or(api_sleep)
        .with(warp::log(clap::crate_name!()));
    warp::serve(routes).run((interface, port)).await;
}
