---
title: ZERO TO PRODUCTION IN RUST
subtitle: Chapter 3 Part 2
theme: serif
date: 02 Feb 2024
---
<style type="text/css">
  .reveal {
    font-size: 28px;
  }

  .reveal h1 {
    font-size: 60px;
  }

  .reveal p {
    text-align: left;
  }
  .reveal ul {
    display: block;
  }
  .reveal ol {
    display: block;
  }
</style>

### Where were we left?

- 3.5 Writing our first integration test (Page 39)
- Book has its own repository: \
    https://github.com/LukeMathWalker/zero-to-production.git
- There are branches for each chapter, so you can keep track of the code along the book

---

### 3.6. Refocus

- Requirement: \
    As a blog visitor, \
    I want to subscribe to the newsletter, \
    So that I can receive email updates when new content is published on the blog.

---

### What we will achieve

- how to read data collected in a HTML form in actix-web (i.e. how do I parse the request body of a POST?)
- what libraries are available to work with a PostgreSQL database in Rust (diesel vs sqlx vs tokio-postgres)
- how to setup and manage migrations for our database
- how to get our hands on a database connection in our API request handlers
- how to test for side-effects (a.k.a. stored data) in our integration tests
- how to avoid weird interactions between tests when working with a database.

---

### 3.7 Working With HTML Forms

---

### 3.7.1 Refining out requirements

- What information do we need?
  - email
  - name
  - if either is missing, 400 BAD REQUEST
- Html form, content-type: `application/x-www-form-urlencoded` \
  (key-value pairs encoded in the body of the request as url encoded)
- Other options
  - Html form, content-type: `text/plain`, `application/json` or `application/xml`
  - Query string

---

### 3.7.2 Capturing Our Requirements As Tests

- test driven development
- `subscribe_returns_a_200_for_valid_form_data`
- `subscribe_returns_a_400_when_data_is_missing`
- parameterized tests, rstest does it better

---

rstest version

``` rust
#[rstest]
#[case(("name=le%20guin", "missing the email"))]
#[case(("email=ursula_le_guin%40gmail.com", "missing the name"))]
#[case(("", "missing both name and email"))]
async fn subscribe_returns_a_400_when_data_is_missing(#[case] test_case: (&str, &str)) {
    let app = spawn_app().await;
    let client = request::Client::new();

    let (invalid_body, error_message) = test_case
    let response = client
        .post(&format!("{}/subscriptions", &app.address))
        .header("Content-Type", "application/x-www-form-urlencoded")
        .body(invalid_body)
        .send()
        .await
        .expect("Failed to execute request.");

    assert_eq!(
        400,
        response.status().as_u16(),
        "The API did not fail with 400 Bad Request when the payload was {}.",
        error_message
    );
}
```

---

### 3.7.3 Parsing Form Data From A POST Request

- First, we need a new route for subscriptions

```rust
// Let's start simple: we always return a 200 OK
async fn subscribe() -> HttpResponse {
  HttpResponse::Ok().finish()
}

pub fn run(listener: TcpListener, db_pool: PgPool) -> Result<Server, std::io::Error> {
    let db_pool = Data::new(db_pool);
    let server = HttpServer::new(move || {
        App::new()
            .route("/health_check", web::get().to(health_check))
            .route("/subscriptions", web::post().to(subscribe))
            .app_data(db_pool.clone())
    })
    .listen(listener)?
    .run();
    Ok(server)
}
```

---

### 3.7.3.1 Extractors

- Some use cases
  - Type-safe information extraction from requests
  - Path to get dynamic path segments from a request’s path
  - Query for query parameters
  - Json to parse a JSON-encoded request body
  
- Form extractor, `web::Form<YourType>` \
  Parses the request body according to the contents your type.

``` rust
#[derive(serde::Deserialize)]
pub struct FormData {
    email: String,
    name: String,
}

pub async fn subscribe(form: web::Form<FormData>) -> HttpResponse {
  println!("{} {}", form.email, form.name);
  HttpResponse::Ok().finish()
}
```

---

Other kind of Extractors

- `web::Path<>` => Parses path parameters: `www.example.com/users/{user_id}/friends/{friend_id}`
- `web::Query<>` => Parses query parameters: `www.example.com/users?sort={sort_id}&limit={limit_id}`
- `web::Json<>` => Parses JSON encoded request body  
- `web::Header<>` => Parses request headers
- `web::Data<>` => Access to application state
- `web::Bytes` => Access to request body as bytes

---

### 3.7.3.2 Form And FromRequest

``` rust
#[derive(PartialEq, Eq, PartialOrd, Ord)]
pub struct Form<T>(pub T);
```

``` rust
pub trait FromRequest: Sized {
  type Error = Into<actix_web::Error>;

  async fn from_request(
    req: &HttpRequest,
    payload: &mut Payload
  ) -> Result<Self, Self::Error>
}
```

``` rust
impl<T> FromRequest for Form<T>
where T: DeserializeOwned + 'static,
{
  type Error = actix_web::Error;
  async fn from_request(
    req: &HttpRequest,
    payload: &mut Payload
  ) -> Result<Self, Self::Error> {
    // Omitted stuff around extractor configuration (e.g. payload size limits)
    match UrlEncoded::new(req, payload).await {
      Ok(item) => Ok(Form(item)),
      // The error handler can be customized.
      Err(e) => Err(error_handler(e))
    }
  }
}
```

---

### 3.7.3.3 Serialization In Rust: serde

- SERialization/DEserialization
- Serde is the most popular serialization and deserialization framework for common Rust data structures
  - generically: Serde only defines the traits, it does not provide any particular implementation. Each data format is supported by a separate crate (serde_json, serde_urlencoded etc...)
  - efficiently:  Monomorphization is the process of turning generic code into specific code by filling in the concrete types that are used, in compile time
  - conveniently: `#[derive(Serialize)]` and `#[derive(Deserialize)]`, automatically generate the code for serialization and deserialization.
- Serde supports: URL query encoding, JSON, YAML, TOML, CSV, Pickle and 16 others. (including binary formats)

---

Serde example

``` rust
use serde::{Deserialize, Serialize};
use serde_json::Result;

#[derive(Serialize, Deserialize)]
struct Person {
    name: String,
    age: u8,
    phones: Vec<String>,
}

fn parse_person() -> Result<()> {
    let data = r#"
        {
            "name": "John Doe",
            "age": 43,
            "phones": [ "+44 1234567" ]
        }"#;
    let p: Person = serde_json::from_str(data)?;
    Ok(())
}
```

---

### 3.8 Storing Data: Databases

Anything that we save on disk would only be available to one of the many replicas of our application.
Furthermore, it would probably disappear if the underlying host crashed.
This explains why Cloud-native applications are usually stateless: their persistence needs are delegated to specialized external systems - databases.

---

### 3.8.1 Choosing A Database

- If you are uncertain about your persistence requirements, use a relational database. \
  If you have no reason to expect massive scale, use PostgreSQL

- From a data-model perspective, the NoSQL movement has brought us document-stores (e.g. MongoDB),
  - Key-value stores (e.g. AWS DynamoDB), graph databases (e.g. Neo4J), etc.
  - We have databases that use RAM as their primary storage (e.g. Redis).
  - We have databases that are optimized for analytical queries via columnar storage (e.g. AWS RedShift).

---

### 3.8.2 Choosing A Database Crate

- Most used creates for interacting with a PostgreSQL database:
  - tokio-postgres (425,578)
  - sqlx (849,174)
  - diesel (332,126)

- What should we consider when picking one?
  - Compile-time safety
  - Query Interface
  - Async support

---

What should we consider when picking one? (1/3)

- Compile-time safety: (sqlx and diesel)
  - Catch errors at compile time
  - Detect typos in sql queries
  - Change a column name in the database, but forgot reflecting to code in one of the queries

---

What should we consider when picking one? (2/3)

- Query Interface:
  - SQL-first: (sqlx and tokio-postgres)\
    Write direct SQL queries inside rust code \
    advantages: fast, reliable \
    disadvantages: database dependant

  - DSL: (diesel) \
  write Rust code which is implicitly translated to sql \
  advantages: database independent \
  disadvantages: might be slow with complex queries, can't fine tune
  ```rust
      fn main() {
          use self::schema::posts::dsl::*;

          let connection = &mut establish_connection();
          let results = posts
              .filter(published.eq(true))
              .limit(5)
              .select(Post::as_select())
              .load(connection)
              .expect("Error loading posts");
      }
  ```

---

What should we consider when picking one? (3/3)

- Async support: \
  Threads are for working in parallel, async is for waiting in parallel.
  - tokio-postgres and sqlx have built-in support
  - diesel doesn't have build-in async support, needs a thread pool, which might be costly. \
  (although a separate create, diesel-async, has been released very recently, v0.4)

---

### 3.8.3 Integration Testing With Side-effects

- The first integration tests in this chapter were stateless, they did not interact with the database to check if the data was stored correctly.
- There are 2 options to check for side-effects:
  - leverage another endpoint of our public API to inspect the application state: Needs another api endpoint, which we don't have currently
  - query directly the database in our test case: Let's pick this temporarily, we will go back to first option later

---

### 3.8.4 Database Setup

- a running Postgres instance;
- a table to store our subscribers data.

---

### 3.8.4.1 Docker

- write a bash script for initializing the database

---

### 3.8.4.2 Database Migration

- Database migration is the process of transforming a database from one state to another.
- sqlx has a built-in migration tool, sqlx-cli (other crates have too)
- To install  
    sqlx setup, cargo install --version="~0.7" sqlx-cli --no-default-features --features rustls,postgres

---

psql setup, $env:PATH += ";C:\Program Files\PostgreSQL\16\bin"
sqlx setup, cargo install --version="~0.7" sqlx-cli --no-default-features --features rustls,postgres