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

- a running Postgres instance, using docker
- a database table to store our subscribers data

---

### 3.8.4.1 Docker

- Write a bash script for initializing the database

``` sh
docker run \
  -e POSTGRES_USER=${DB_USER} \
  -e POSTGRES_PASSWORD=${DB_PASSWORD} \
  -e POSTGRES_DB=${DB_NAME} \
  -p "${DB_PORT}":5432 \
  -d postgres \
  postgres -N 1000
```

- Check if docker instance is up and postgresql is ready and running.

``` sh
# Keep pinging Postgres until it's ready to accept commands
export PGPASSWORD="${DB_PASSWORD}"
until psql -h "localhost" -U "${DB_USER}" -p "${DB_PORT}" -d "postgres" -c '\q'; do
  >&2 echo "Postgres is still unavailable - sleeping"
  sleep 1
done
```


---

### 3.8.4.2 Database Migrations

- Database migration is the process of transforming the database schema from one state to another. \
They are kind of a version control system for database schemas.

- sqlx has a built-in migration tool called sqlx-cli (other crates have similar tools, too)
- Install sqlx-cli, not included in the sqlx crate

``` sh
    cargo install --version="~0.7" sqlx-cli --no-default-features --features rustls,postgres
```

- Create the database using sqlx-cli

``` sh
DATABASE_URL=postgres://${DB_USER}:${DB_PASSWORD}@localhost:${DB_PORT}/${DB_NAME}
export DATABASE_URL
sqlx database create
```

---

- Let's create our first migration

``` sh
sqlx migrate add create_subscriptions_table
```

- This will create a folder called migrations, and create an sql file called {timestamp}_create_subscriptions_table.sql. \
  We should put the necessary sql statement for creating the subscriptions table there

``` sql
-- Create Subscriptions Table
-- We are enforcing that all fields should be populated with a NOT NULL constraint on each column
-- We are enforcing email uniqueness at the database-level with a UNIQUE constraint
CREATE TABLE subscriptions(
  id uuid NOT NULL,
  PRIMARY KEY (id),
  email TEXT NOT NULL UNIQUE,
  name TEXT NOT NULL,
  subscribed_at timestamptz NOT NULL
);
```

- Finally, run/apply the migration(s)

``` sh
sqlx migrate run
```

--- 

### 3.8.5 Writing Our First Query

- Necessary sqlx features in cargo.toml

``` toml
[dependencies.sqlx]
version = "0.6"
default-features = false
features = [
  "runtime-tokio-rustls", # sqlx uses the tokio runtime for its futures and rustls as TLS backend
  "macros", # macro support, sqlx::query! and qlx::query_as! 
  "postgres", # non-standard postgres types
  "uuid", # enable SQL uuid type, using another crate
  "chrono", # mapping SQL timestamptz to the DateTime<T>
  "migrate", # enable migrations even without sqlx-cli
]

```

---

- For configuration management, we rely on `config` crate (735,744). \
  All the relevant application parameters are going to be kept in configuration.yaml file. \
  (Kept plain text?).

``` rust
// src/configuration.rs
#[derive(serde::Deserialize)]
pub struct Settings {
  pub database: DatabaseSettings,
  pub application_port: u16
}

#[derive(serde::Deserialize)]
pub struct DatabaseSettings {
  pub username: String,
  pub password: String,
  pub port: u16,
  pub host: String,
  pub database_name: String,
}
```

---

- In the very same `configuration.rs` file, let's add a helper for reading configuration. It will be called from main during application start.

``` rust
pub fn get_configuration() -> Result<Settings, config::ConfigError> {
  // Initialise our configuration reader
  let settings = config::Config::builder()
    // Add configuration values from a file named `configuration.yaml`.
    .add_source(
      config::File::new("configuration.yaml", config::FileFormat::Yaml)
    )
    .build()?;
  // Try to convert the configuration values it read into
  // our Settings type
  settings.try_deserialize::<Settings>()
}
```

---

- Connecting To Postgres is done through `PgConnection::connect`, which needs a single connection string. Let's add a utility function to `DatabaseSettings` for constructing the connection string based on configuration.yml

``` rust
//! src/configuration.rs
impl DatabaseSettings {
pub fn connection_string(&self) -> String {
  format!(
    "postgres://{}:{}@{}:{}/{}",
    self.username, self.password, self.host, self.port, self.database_name
    )
  }
}
```

- This will create a PgConnection instance, connected to the database:

``` rust
let connection_string = configuration.database.connection_string();
// The `Connection` trait MUST be in scope for us to invoke
// `PgConnection::connect` - it is not an inherent method of the struct!
let connection = PgConnection::connect(&connection_string)
  .await
  .expect("Failed to connect to Postgres.");
```

---

- Finally we can add checks in our tests, to see if the data is really written to the database (3.8.3)
