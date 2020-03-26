require "spec"
require "kemal"
require "spec-kemal"
require "../src/kemal-session-postgres"

class DBHelper
  property initial_db_uri : String = ENV["DB_URL"],
    test_db_uri : String = ENV["DB_URL"].gsub(/^(.+)\/.+?$/, "\\1/kemal_sessions_testdb"),
    initial_db : DB::Database,
    test_db : DB::Database

  def initialize
    @initial_db = ::DB.open(@initial_db_uri)
    if @initial_db.scalar("SELECT COUNT(oid) > 0 FROM pg_database WHERE datname = 'kemal_sessions_testdb'").as(Bool)
      @initial_db.exec("DROP DATABASE kemal_sessions_testdb")
    end
    @initial_db.exec("CREATE DATABASE kemal_sessions_testdb")
    @test_db = ::DB.open(@test_db_uri)
  end
end

DB_HELPER = DBHelper.new

Spec.before_each do
  if DB_HELPER.test_db.scalar("SELECT COUNT(tablename) > 0 FROM pg_tables WHERE tablename = 'kemal_sessions_test'").as(Bool)
    DB_HELPER.test_db.exec("TRUNCATE TABLE kemal_sessions_test")
  end

  Kemal::Session.config.secret = "super-awesome-secret"
  Kemal::Session.config.engine = Kemal::Session::PostgresEngine.new(DB_HELPER.test_db, sessions_table: "kemal_sessions_test")
end

SESSION_ID = Random::Secure.hex

def get_from_db(session_id : String)
  DB_HELPER.test_db.query_one "SELECT data FROM kemal_sessions_test WHERE session_id = $1", session_id, &.read(String)
end

def create_context(session_id : String)
  response = HTTP::Server::Response.new(IO::Memory.new)
  headers = HTTP::Headers.new

  unless session_id == ""
    Kemal::Session.config.engine.create_session(session_id)
    cookies = HTTP::Cookies.new
    cookies << HTTP::Cookie.new(Kemal::Session.config.cookie_name, Kemal::Session.encode(session_id))
    cookies.add_request_headers(headers)
  end

  request = HTTP::Request.new("GET", "/", headers)
  return HTTP::Server::Context.new(request, response)
end

class UserJsonSerializer
  JSON.mapping({
    id:   Int32,
    name: String,
  })
  include Kemal::Session::StorableObject

  def initialize(@id : Int32, @name : String); end

  def serialize
    self.to_json
  end

  def self.unserialize(value : String)
    UserJsonSerializer.from_json(value)
  end
end
