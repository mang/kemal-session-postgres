# kemal-session-postgres

This is a postgres adaptor for [Kemal Session](https://github.com/kemalcr/kemal-session), with built-in cache and support for syncing cache states across multiple engine instances through postgres NOTIFY command.

Based on [kemal-session-mysql](https://github.com/mang/kemal-session-mysql)

## Installation

Add this to your application's `shard.yml`:

```yaml
dependencies:
  kemal-session-postgres:
    github: mang/kemal-session-postgres
```

## Usage

```crystal
require "kemal"
require "kemal-session-postgres"
require "pg"

# connect to postgres, update url with your connection info (or perhaps use an ENV var)
connection = DB.open "postgres://youruser:yourpassword@localhost/yourdb"

Session.config do |config|
  config.engine = Session::PostgresEngine.new(connection)
end
```

If you are already using crystal-pg you can re-use the reference to your connection.

## Optional Parameters

```
Session.config do |config|
  config.engine = Session::PostgresEngine.new(
    connection: connection,
    sessions_table: "kemal_sessions",
    propagate_strategy: :invalidate # or :update
    cache_ttl: 60.seconds
  )
end
```
|Param              |Description
|----               |----
|connection         | A Crystal Postgres DB Connection
|sessions_table     | Name of the table to use for sessions - defaults to "kemal_sessions"
|propagate_strategy | Choose how to handle local caches when database is updated. :invalidate (default), deletes the local cache entry, while :update queries the database and updates the local cache
|cache_ttl          | Number of seconds to hold the session data in memory, before re-reading from the database. This is set to 60 seconds by default, set to 0 to hit the db for every request.

## Testing
Run `crystal spec` with `KEMAL_ENV=test` and `DB_URL` set to any database with permission to create new databases.

**Warning:** When running specs a database named `kemal_sessions_testdb` will be created and overwritten.

## Contributing

1. Fork it ( https://github.com/mang/kemal-session-postgres/fork )
2. Create your feature branch (git checkout -b my-new-feature)
3. Commit your changes (git commit -am 'Add some feature')
4. Push to the branch (git push origin my-new-feature)
5. Create a new Pull Request

## Contributors

- [mang](https://github.com/mang) Maggie Soltani - creator, maintainer
