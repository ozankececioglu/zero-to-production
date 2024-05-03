//! src/routes/subscriptions_confirm.rs
use actix_web::{HttpResponse, web};

// !### 15 Add a new handler
// #[tracing::instrument(name = "Confirm a pending subscriber")]
// pub async fn confirm() -> HttpResponse {
//     HttpResponse::Ok().finish()
// }

// !### 16
#[derive(serde::Deserialize)]
pub struct Parameters {
    subscription_token: String,
}

#[tracing::instrument(name = "Confirm a pending subscriber", skip(_parameters))]
pub async fn confirm(_parameters: web::Query<Parameters>) -> HttpResponse {
    HttpResponse::Ok().finish()
}
