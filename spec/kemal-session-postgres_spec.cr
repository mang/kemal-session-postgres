require "./spec_helper"
require "http/client"

describe Kemal::Session::Postgres do
  describe ".int" do
    it "can save a value" do
      session = Kemal::Session.new(create_context(SESSION_ID))
      session.int("int", 12)
    end

    it "can retrieve a saved value" do
      session = Kemal::Session.new(create_context(SESSION_ID))
      session.int("int", 12)
      get_from_db(SESSION_ID).should eq(%{{"ints":{"int":12},"bigints":{},"strings":{},"floats":{},"bools":{},"objects":{}}})
      session.int("int").should eq 12
    end
  end

  describe ".bool" do
    it "can save a value" do
      session = Kemal::Session.new(create_context(SESSION_ID))
      session.bool("bool", true)
    end

    it "can retrieve a saved value" do
      session = Kemal::Session.new(create_context(SESSION_ID))
      session.bool("bool", true)
      session.bool("bool").should eq true
    end
  end

  describe ".float" do
    it "can save a value" do
      session = Kemal::Session.new(create_context(SESSION_ID))
      session.float("float", 3.00)
    end

    it "can retrieve a saved value" do
      session = Kemal::Session.new(create_context(SESSION_ID))
      session.float("float", 3.00)
      session.float("float").should eq 3.00
    end
  end

  describe ".string" do
    it "can save a value" do
      session = Kemal::Session.new(create_context(SESSION_ID))
      session.string("string", "kemal")
    end

    it "can retrieve a saved value" do
      session = Kemal::Session.new(create_context(SESSION_ID))
      session.string("string", "kemal")
      session.string("string").should eq "kemal"
    end
  end

  describe ".object" do
    it "can be saved and retrieved" do
      session = Kemal::Session.new(create_context(SESSION_ID))
      u = UserJsonSerializer.new(123, "charlie")
      session.object("user", u)
      new_u = session.object("user").as(UserJsonSerializer)
      new_u.id.should eq(123)
      new_u.name.should eq("charlie")
    end
  end

  describe ".destroy" do
    it "should remove session from postgres" do
      session = Kemal::Session.new(create_context(SESSION_ID))
      value = DB_HELPER.test_db.scalar("SELECT COUNT(session_id) FROM kemal_sessions_test WHERE session_id = $1", SESSION_ID)
      value.should eq(1)
      session.destroy
      value = DB_HELPER.test_db.scalar("SELECT COUNT(session_id) FROM kemal_sessions_test WHERE session_id = $1", SESSION_ID)
      value.should eq(0)
    end
  end

  describe "#destroy" do
    it "should remove session from postgres" do
      session = Kemal::Session.new(create_context(SESSION_ID))
      value = DB_HELPER.test_db.scalar("SELECT COUNT(session_id) FROM kemal_sessions_test WHERE session_id = $1", SESSION_ID)
      value.should eq(1)
      Kemal::Session.destroy(SESSION_ID)
      value = DB_HELPER.test_db.scalar("SELECT COUNT(session_id) FROM kemal_sessions_test WHERE session_id = $1", SESSION_ID)
      value.should eq(0)
    end

    it "should succeed if session doesnt exist in postgres" do
      session = Kemal::Session.new(create_context(SESSION_ID))
      value = DB_HELPER.test_db.scalar("SELECT COUNT(session_id) FROM kemal_sessions_test WHERE session_id = $1", SESSION_ID)
      value.should eq(1)
      Kemal::Session.destroy(SESSION_ID).should be_truthy
    end
  end

  describe "#destroy_all" do
    it "should remove all sessions in postgres" do
      5.times { Kemal::Session.new(create_context(Random::Secure.hex)) }
      arr = Kemal::Session.all
      arr.size.should eq(5)
      Kemal::Session.destroy_all
      Kemal::Session.all.size.should eq(0)
    end
  end

  describe "#get" do
    it "should return a valid Session" do
      session = Kemal::Session.new(create_context(SESSION_ID))
      get_session = Kemal::Session.get(SESSION_ID)
      get_session.should_not be_nil
      if get_session
        session.id.should eq(get_session.id)
        get_session.is_a?(Kemal::Session).should be_true
      end
    end

    it "should return nil if the Session does not exist" do
      session = Kemal::Session.get(SESSION_ID)
      session.should be_nil
    end
  end

  describe "#create" do
    it "should build an empty session" do
      Kemal::Session.config.engine.create_session(SESSION_ID)
      value = DB_HELPER.test_db.scalar("SELECT COUNT(session_id) FROM kemal_sessions_test WHERE session_id = $1", SESSION_ID)
      value.should eq(1)
    end
  end

  describe "#all" do
    it "should return an empty array if none exist" do
      arr = Kemal::Session.all
      arr.is_a?(Array).should be_true
      arr.size.should eq(0)
    end

    it "should return an array of Sessions" do
      3.times { Kemal::Session.new(create_context(Random::Secure.hex)) }
      arr = Kemal::Session.all
      arr.is_a?(Array).should be_true
      arr.size.should eq(3)
    end
  end

  describe "#each" do
    it "should iterate over all sessions" do
      5.times { Kemal::Session.new(create_context(Random::Secure.hex)) }
      count = 0
      Kemal::Session.each do |session|
        count = count + 1
      end
      count.should eq(5)
    end
  end

  it "caches db session data" do
    get "/user/:user_name" do |env|
      user_name = env.params.url["user_name"]
      env.session.string("user_name", user_name)
      env.session.string("user_name")
    end

    get "/user" do |env|
      env.session.string("user_name")
    end

    engines = [] of Kemal::Session::Engine
    session_keys = [] of String
    session_user_names = [] of String
    cookie = ""

    # run two servers (and session engines) in sequence
    2.times do |i|
      Kemal::Session.config do |c|
        c.secret = "superrandom"
        c.engine = Kemal::Session::PostgresEngine.new(DB_HELPER.test_db, sessions_table: "kemal_sessions_test", propagate_strategy: :update)
        engines << c.engine
      end

      Kemal.run

      if i == 0
        # set the user name only on the first server
        get "/user/maggie"
        cookie = response.headers["Set-Cookie"]
        response.body.should eq "maggie"
      elsif i == 1
        # the value should be read from db to the second server
        get "/user", HTTP::Headers{"Cookie" => cookie}
        response.body.should eq "maggie"
      end
    end

    engines.each do |engine|
      engine.as(Kemal::Session::PostgresEngine).cache.each_key do |key|
        session_keys << key
      end
      engine.as(Kemal::Session::PostgresEngine).cache.each_value do |value|
        session_user_names << value.strings["user_name"]?.to_s
      end
    end

    # compare session caches, did the second server cache the session data?
    session_keys.size.should eq 2
    session_keys.uniq.size.should eq 1
    session_user_names.reject { |x| x.empty? }.should eq ["maggie", "maggie"]
  end

  it "propagates cache updates to connected session engines" do
    get "/user2/:user_name" do |env|
      user_name = env.params.url["user_name"]
      env.session.string("user_name", user_name)
      env.session.string("user_name")
    end

    engines = [] of Kemal::Session::Engine
    session_keys = [] of String
    session_user_names = [] of String

    # run two servers (and session engines) in sequence
    2.times do |i|
      spawn do
        Kemal::Session.config do |c|
          c.secret = "superrandom"
          c.engine = Kemal::Session::PostgresEngine.new(DB_HELPER.test_db, sessions_table: "kemal_sessions_test", propagate_strategy: :update)
          engines << c.engine
        end

        Kemal.run do |conf|
          server = conf.server.not_nil!
          server.bind_tcp "0.0.0.0", 3001, reuse_port: true
        end

        if i == 0
          spawn do
            sleep 0.2 # wait for second server/session engine to start up
            # set the user name only on the first server, the second should receive it from PG notify
            get "/user2/yolo"
            response.body.should eq "yolo"
          end
        end
      end
      sleep 0.1 # avoid race condition in db ("create table if not exists") in PostgresEngine initialization
    end
    sleep 0.3 # wait for all above to finnish before running test assertions

    engines.each do |engine|
      engine.as(Kemal::Session::PostgresEngine).cache.each_key do |key|
        session_keys << key
      end
      engine.as(Kemal::Session::PostgresEngine).cache.each_value do |value|
        session_user_names << value.strings["user_name"]?.to_s
      end
    end

    # compare session caches, did they propagate to the second server?
    session_keys.size.should eq 2
    session_keys.uniq.size.should eq 1
    session_user_names.sort.should eq ["yolo", "yolo"]
  end

  it "propagates cache deletions to connected session engines" do
    get "/user3/:user_name" do |env|
      user_name = env.params.url["user_name"]
      env.session.string("user_name", user_name)
      env.session.string("user_name")
    end

    get "/logout" do |env|
      env.session.destroy
    end

    engines = [] of Kemal::Session::Engine
    session_keys = [] of String
    session_user_names = [] of String
    cookie = ""

    # run two servers (and session engines) in sequence
    2.times do |i|
      spawn do
        Kemal::Session.config do |c|
          c.secret = "superrandom"
          c.engine = Kemal::Session::PostgresEngine.new(DB_HELPER.test_db, sessions_table: "kemal_sessions_test", propagate_strategy: :update)
          engines << c.engine
        end

        Kemal.run do |conf|
          server = conf.server.not_nil!
          server.bind_tcp "0.0.0.0", 3001, reuse_port: true
        end

        if i == 0
          spawn do
            sleep 0.2 # wait for second server/session engine to start up
            # set the user name only on the first server, the second should receive it from PG notify
            get "/user3/maggie"
            response.body.should eq "maggie"
            cookie = response.headers["Set-Cookie"]

            sleep 0.2 # wait for caches to propagate
            # set the user name only on the first server, the second should receive it from PG notify
            get "/logout", HTTP::Headers{"Cookie" => cookie}
          end
        end
      end
      sleep 0.1 # avoid race condition in db ("create table if not exists") in PostgresEngine initialization
    end
    sleep 0.5 # wait for all above to finnish before running test assertions

    engines.each do |engine|
      engine.as(Kemal::Session::PostgresEngine).cache.each_key do |key|
        session_keys << key
      end
      engine.as(Kemal::Session::PostgresEngine).cache.each_value do |value|
        session_user_names << value.strings["user_name"]?.to_s
      end
    end

    # compare session caches, did they propagate to the second server?
    session_keys.size.should eq 0
    session_keys.uniq.size.should eq 0
    session_user_names.sort.should eq [] of String
  end

  it "propagates cache invalidations to connected session engines" do
    get "/user4/:user_name" do |env|
      user_name = env.params.url["user_name"]
      env.session.string("user_name", user_name)
      env.session.string("user_name")
    end

    engines = [] of Kemal::Session::Engine
    session_engine_ids = [] of String
    session_keys = [] of String
    session_user_names = [] of String

    # run two servers (and session engines) in sequence
    2.times do |i|
      spawn do
        Kemal::Session.config do |c|
          c.secret = "superrandom"
          c.engine = Kemal::Session::PostgresEngine.new(DB_HELPER.test_db, sessions_table: "kemal_sessions_test", propagate_strategy: :invalidate)
          engines << c.engine
        end

        Kemal.run do |conf|
          server = conf.server.not_nil!
          server.bind_tcp "0.0.0.0", 3001, reuse_port: true
        end

        if i == 0
          spawn do
            sleep 0.2 # wait for second server/session engine to start up
            # set the user name only on the first server, the second should receive it from PG notify
            get "/user4/laleh"
            response.body.should eq "laleh"
          end
        end
      end
      sleep 0.1 # avoid race condition in db ("create table if not exists") in PostgresEngine initialization
    end
    sleep 0.3 # wait for all above to finnish before running test assertions

    engines.each do |engine|
      engine.as(Kemal::Session::PostgresEngine).cache.each_key do |key|
        session_keys << key
      end
      engine.as(Kemal::Session::PostgresEngine).cache.each_value do |value|
        session_user_names << value.strings["user_name"]?.to_s
      end
    end

    # compare session caches, did they propagate to the second server?
    session_keys.size.should eq 1
    session_keys.uniq.size.should eq 1
    session_user_names.sort.should eq ["laleh"]
  end
end
