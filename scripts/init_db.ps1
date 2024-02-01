function value_or_default($param, $default) {
    if ($param -eq $null) {
        return $default
    }
    return $param
}

# Check if a custom user has been set, otherwise default to 'postgres'
$DB_USER = value_or_default($env:ZERO2PROD_POSTGRES_USER, "postgress")
# Check if a custom password has been set, otherwise default to 'password'
$DB_PASSWORD = value_or_default($env:ZERO2PROD_POSTGRES_PASSWORD, "password")
# Check if a custom database name has been set, otherwise default to 'newsletter'
$DB_NAME = value_or_default($env:ZERO2PROD_POSTGRES_DB, "newsletter")
# Check if a custom port has been set, otherwise default to '5432'
$DB_PORT = value_or_default($env:ZERO2PROD_POSTGRES_PORT, 5432)
# Check if a custom host has been set, otherwise default to 'localhost'
$DB_HOST = value_or_default($env:ZERO2PROD_POSTGRES_HOST, "localhost")

$result = docker ps --filter 'name=postgres' --format '{{.ID}}'
if ($result -eq "") {
    Write-Error "there is a postgres container already running, kill it with docker kill ${result}"
    exit 1
}

docker run `
    -e POSTGRES_USER=$DB_USER `
    -e POSTGRES_PASSWORD=$DB_PASSWORD `
    -e POSTGRES_DB=$DB_NAME `
    -p $($DB_PORT):5432 `
    -d `
    -name postgres_$([System.DateTimeOffset]::Now.ToUnixTimeSeconds())`
    postgres -N 1000

$env:PATH += ";C:\Users\ozan\ws\trash\bin\postgresql-bin"

while ($true) {
    $result = psql -h "${DB_HOST}" -U "${DB_USER}" -p "${DB_PORT}" -d "postgres" -c '\q'
    if ($result -eq "") {
        break
    }
}
    
echo "Postgres is up and running on port ${DB_PORT} - running migrations now!"

$env:DATABASE_URL="postgresql://${DB_USER}:${DB_PASSWORD}@${DB_HOST}:${DB_PORT}/${DB_NAME}"
sqlx database create
sqlx migrate run

echo "Postgres has been migrated, ready to go!"