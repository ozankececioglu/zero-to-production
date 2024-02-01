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
- Html form content-type
  - `application/x-www-form-urlencoded` \
  (key-value pairs encoded in the body of the request as url encoded)
  - other options: `text/plain`, `application/json`, `application/xml`

--- 


### 3.7.2 Capturing Our Requirements As Tests

- test driven development
- `subscribe_returns_a_200_for_valid_form_data`
- `subscribe_returns_a_400_when_data_is_missing`
- parameterized tests, show a rstest example

--- 

### 3.7.3 Parsing Form Data From A POST Request

- adding a new route

---

### 3.7.3.1 Extractors

- Use cases
  - Type-safe information extraction from requests
  - Path to get dynamic path segments from a request’s path
  - Query for query parameters
  - Json to parse a JSON-encoded request body
- Form extractor, web::Form<>  =>  request body is url encoded
- Other Extractors
  - `web::Path<>` => `www.example.com/users/{user_id}/friends/{friend_id}`
  - `web::Query<>` => `www.example.com/users?sort={sort_id}&limit={limit_id}`
  - `web::Json<>` => request body is JSON
  - `web::Data<>` => application state
  - `web::Bytes` => request body as bytes

---

### 3.7.3.2 Form And FromRequest

- ???

---

### 3.7.3.3 Serialization In Rust: serde

- SERialization/DEserialization
- Serde is a framework for serializing and deserializing most common Rust data structures 
  - generically: Serde only defines the traits, it does not provide any particular implementation. Each data format is supported by a separate crate (serde_json, serde_urlencoded etc...)
  - efficiently:  Monomorphization is the process of turning generic code into specific code by filling in the concrete types that are used, in compile time
  - conveniently: `#[derive(Serialize)]` and `#[derive(Deserialize)]`, automatically generate the code for serialization and deserialization. 
- Serde supports: URL query encoding, JSON, YAML, TOML, CSV, Pickle and 16 others. (including binary formats)

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
  - tokio-postgres
  - sqlx
  - diesel

---

- What should we consider when picking one?
  - Compile-time safety: catch errors at compile time (sqlx and diesel)
  - SQL-first vs a Domain specific language (DSL) for query building: 
    - SQL-first: write SQL queries and have them checked at compile time \
    (sqlx and tokio-postgres)
    - DSL: write Rust code that is then translated into SQL queries \
    (diesel)
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
    - async vs sync interface (sqlx and tokio-postgresql)

---
    
### 3.8.3 Integration Testing With Side-effects

- Previous integration tests were stateless, they did not interact with the database to check if the data was stored correctly.
- There are 2 options to check for side-effects:
  - leverage another endpoint of our public API to inspect the application state: Needs another api endpoint, which we don't have currently
  - query directly the database in our test case: Let's pick this temporarily, we will go back to first option later when we write an endpoint

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