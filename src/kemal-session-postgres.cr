require "db"
require "pg"
require "json"
require "kemal-session"

module Kemal::Session::Postgres
  VERSION = "0.1.0"
end

module Kemal
  class Session
    class PostgresEngine < Engine
      class StorageInstance
        macro define_storage(vars)
          JSON.mapping(
            {
              {% for name, type in vars %}
                  {{name.id}}s: Hash(String, {{type}}),
              {% end %}
            }
          )

          {% for name, type in vars %}
            @{{name.id}}s = Hash(String, {{type}}).new
            getter {{name.id}}s

            def {{name.id}}(k : String) : {{type}}
              return @{{name.id}}s[k]
            end

            def {{name.id}}?(k : String) : {{type}}?
              return @{{name.id}}s[k]?
            end

            def {{name.id}}(k : String, v : {{type}})
              @{{name.id}}s[k] = v
            end

            def delete_{{name.id}}(k : String)
              if @{{name.id}}s[k]?
                @{{name.id}}s.delete(k)
              end
            end
          {% end %}

          def initialize
            {% for name, type in vars %}
              @{{name.id}}s = Hash(String, {{type}}).new
            {% end %}
          end
        end

        define_storage(
          {
            int:    Int32,
            bigint: Int64,
            string: String,
            float:  Float64,
            bool:   Bool,
            object: Session::StorableObject::StorableObjectContainer,
          }
        )
      end

      property cache = {} of String => StorageInstance,
        cache_times = {} of String => Time,
        db_conn : DB::Database,
        cache_ttl : Time::Span

      def initialize(@db_conn : DB::Database, @sessions_table = "kemal_sessions", @cache_ttl = 60.seconds)
        @db_conn.exec(
          %{
            CREATE TABLE IF NOT EXISTS #{@sessions_table} (
              session_id VARCHAR(36) PRIMARY KEY,
              data TEXT,
              date_updated TIMESTAMP WITH TIME ZONE DEFAULT NULL
            )
          }
        )
      end

      def run_gc
        @db_conn.exec(
          %{
              DELETE FROM #{@sessions_table}
              WHERE date_updated < $2
            }, Time.utc - Kemal::Session.config.timeout
        )
        @cache.each do |id, session|
          if @cache_times[id]? && (Time.utc - @cache_ttl) > @cache_times[id]
            @cache.delete(id)
            @cache_times.delete(id)
          end
        end
      end

      def create_session(id)
        session = StorageInstance.new
        data = session.to_json
        @db_conn.exec(
          %{
              INSERT INTO #{@sessions_table}
              (session_id, data, date_updated)
              VALUES($1, $2, $3)
              ON CONFLICT (session_id)
              DO UPDATE
              SET
                data = EXCLUDED.data,
                date_updated = EXCLUDED.date_updated
            }, id, data, Time.utc
        )
        return session
      end

      def each_session
        @db_conn.query_all(
          %{
              SELECT data
              FROM #{@sessions_table}
            }) do |result|
          json = result.read(String)
          yield StorageInstance.from_json(json)
        end
      end

      def all_sessions : Array(Kemal::Session)
        sessions = [] of StorageInstance
        each_session { |session| sessions << session }
        return sessions
      end

      def get_session(id) : Kemal::Session | Nil
        return Session.new(id) if session_exists?(id)
      end

      def session_exists?(id)
        @db_conn.query_all(
          %{
              SELECT session_id
              FROM #{@sessions_table}
              WHERE session_id = $1
            }, id
        ) do
          return true
        end
        return false
      end

      def destroy_session(id)
        @db_conn.exec(
          %{
              DELETE FROM #{@sessions_table}
              WHERE session_id = $1
            }, id
        )
      end

      def destroy_all_sessions
        @db_conn.exec(
          %{
              TRUNCATE TABLE #{@sessions_table}
            }
        )
      end

      def save_cache(id)
        data = @cache[id].to_json
        @db_conn.exec(
          %{
            UPDATE #{@sessions_table}
            SET
              data = $1,
              date_updated = $2
            WHERE session_id = $3
          }, data, Time.utc, id
        )
      end

      def load_into_cache(id)
        json = ""

        @db_conn.query_one(
          %{
            SELECT DATA
            FROM #{@sessions_table}
            WHERE session_id = $1
          }, id
        ) do |result|
          json = result.read(String)
        end

        if json.empty?
          @cache[id] = create_session(id)
        else
          @cache[id] = StorageInstance.from_json(json)
        end

        @cache_times[id] = Time.utc

        @db_conn.exec(
          %{
            UPDATE #{@sessions_table}
            SET date_updated = $1
            WHERE session_id = $2
          }, Time.utc, id
        )

        @cache[id]
      end

      def is_in_cache?(id)
        return @cache.has_key?(id) &&
          @cache_times.has_key?(id) &&
          @cache_times[id] > (Time.utc - @cache_ttl)
      end

      macro define_delegators(vars)
        {% for name, type in vars %}
          def {{name.id}}(session_id : String, k : String) : {{type}}
            load_into_cache(session_id) unless is_in_cache?(session_id)
            return @cache[session_id].{{name.id}}(k)
          end

          def {{name.id}}?(session_id : String, k : String) : {{type}}?
            load_into_cache(session_id) unless is_in_cache?(session_id)
            return @cache[session_id].{{name.id}}?(k)
          end

          def {{name.id}}(session_id : String, k : String, v : {{type}})
            load_into_cache(session_id) unless is_in_cache?(session_id)
            @cache[session_id].{{name.id}}(k, v)
            save_cache(session_id)
          end

          def {{name.id}}s(session_id : String) : Hash(String, {{type}})
            load_into_cache(session_id) unless is_in_cache?(session_id)
            return @cache[session_id].{{name.id}}s
          end
        {% end %}
      end

      define_delegators({
        int:    Int32,
        bigint: Int64,
        string: String,
        float:  Float64,
        bool:   Bool,
        object: Session::StorableObject::StorableObjectContainer,
      })
    end
  end
end
