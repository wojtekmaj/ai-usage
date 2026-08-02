use std::io::{self, Read};

use ai_usage_core::protocol::{CoreRequest, CoreResponse, handle};

#[tokio::main]
async fn main() {
    let mut input = String::new();
    if let Err(error) = io::stdin().read_to_string(&mut input) {
        write_response(&CoreResponse::failure("inputFailed", error.to_string()));
        return;
    }

    let request = match serde_json::from_str::<CoreRequest>(&input) {
        Ok(request) => request,
        Err(error) => {
            write_response(&CoreResponse::failure("invalidRequest", error.to_string()));
            return;
        }
    };
    write_response(&handle(request).await);
}

fn write_response(response: &CoreResponse) {
    match serde_json::to_string(response) {
        Ok(response) => println!("{response}"),
        Err(error) => println!(
            "{{\"ok\":false,\"error\":{{\"code\":\"serializationFailed\",\"message\":{}}}}}",
            serde_json::to_string(&error.to_string()).unwrap_or_else(|_| "\"unknown\"".to_owned())
        ),
    }
}
