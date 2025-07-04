#!/usr/bin/env ruby
# Encoding: UTF-8

################################################################################
# Extend 'Database' class for connecting to a PostgreSQL database.
# These methods are specific to PostgreSQL.
# Other databases should be implemented in separate gems.
################################################################################

require 'pg'

################################################################################

module Poefy

  class Database

    # Details for the database connection.
    def self.connection
      PG.connect(
        :dbname   => 'poefy',
        :user     => 'poefy',
        :password => 'poefy'
      )
    end

    # Open a class-wide connection, execute a query.
    def self.single_exec! sql, sql_args = nil
      output = nil
      begin
        @@con ||= Database::connection
        output = if sql_args
          @@con.exec(sql, [*sql_args]).values
        else
          @@con.exec(sql).values
        end
      end
      output
    end

    # List all tables in the database.
    # Does not include tables used for testing.
    def self.list
      rs = Database::single_exec! <<-SQL
        SELECT table_name
        FROM information_schema.tables
        WHERE table_schema = 'public';
      SQL
      rs.flatten.reject do |i|
        i.start_with?('spec_')
      end.sort - ['test']
    end

    # Get the description of a table.
    def self.desc table_name
      begin
        sql = "SELECT obj_description($1::regclass, 'pg_class');"
        single_exec!(sql, [table_name]).flatten.first.to_s
      rescue
        ''
      end
    end

    # List all database files and their descriptions.
    def self.list_with_desc
      Database::list.map do |i|
        begin
          [i, Database::desc(i)]
        rescue
          [i, '']
        end
      end.to_h
    end

    ############################################################################

    # This is the type of database that is being used.
    # It is also used as a signifier that a database has been specified.
    def type
      'pg'
    end

    # Get/set the description of the table.
    def desc
      Database::desc table
    end
    def desc=(description)
      safe_desc = description.to_s.gsub("'","''")
      execute! "COMMENT ON TABLE #{table} IS '#{safe_desc}';"
    end

    # The number of lines in the table.
    def count
      return 0 unless exist?
      sql = "SELECT COUNT(*) AS num FROM #{table};"
      execute!(sql).first['num'].to_i
    end

    # See if the table exists or not.
    # Attempt to access table, and return false on error.
    def exist?
      open_connection
      @db.exec("SELECT $1::regclass", [*table])
      true
    rescue PG::UndefinedTable
      false
    end

    # Get all rhyming lines for the word.
    def rhymes word, key = nil
      return nil if word.nil?

      sql = <<-SQL
        SELECT rhyme, final_word, syllables, line
        FROM #{table}
        WHERE rhyme = $1
        ORDER BY rhyme, final_word, syllables, line
      SQL
      output = word.to_phrase.rhymes.keys.map do |rhyme|
        execute!(sql, [rhyme]).to_a
      end.flatten

      if !key.nil? and %w[rhyme final_word syllables line].include?(key)
        output.map!{ |i| i[key] }
      end
      output
    end

    private

      # The name of the table.
      def table
        @name
      end

      # Create a new table.
      def new_connection
        open_connection
      end

      # Open a connection to the database.
      def open_connection
        @db ||= Database::connection
      end

      # Execute a query.
      def execute! sql, *args
        db.exec sql, *args
      end

      # Insert an array of lines.
      def insert_lines table_name, rows
        sql = "INSERT INTO #{table_name} VALUES ( $1, $2, $3, $4 )"
        db.transaction do |db_tr|
          rows.each do |line|
            db_tr.exec sql, line
          end
        end
      end

      ##########################################################################

      # Create the table and the index.
      def create_table table_name, description = nil
        index_name = 'idx_' + table_name
        execute! <<-SQL
          SET client_min_messages TO WARNING;
          DROP INDEX IF EXISTS #{index_name};
          DROP TABLE IF EXISTS #{table_name};
          CREATE TABLE #{table_name} (
            line        TEXT,
            syllables   SMALLINT,
            final_word  TEXT,
            rhyme       TEXT
          );
          CREATE INDEX #{index_name} ON #{table_name} (
            rhyme, final_word, line
          );
        SQL
        self.desc = description
      end

      ##########################################################################

      # Define SQL of the stored procedures.
      def sprocs_sql_hash
        sql = {}
        sql[:rbc] = <<-SQL
          SELECT rhyme, COUNT(rhyme) AS count
          FROM (
            SELECT rhyme, final_word, COUNT(final_word) AS wc
            FROM #{table}
            GROUP BY rhyme, final_word
          ) AS sub_table
          GROUP BY rhyme
          HAVING COUNT(rhyme) >= $1
        SQL
        sql[:rbcs] = <<-SQL
          SELECT rhyme, COUNT(rhyme) AS count
          FROM (
            SELECT rhyme, final_word, COUNT(final_word) AS wc
            FROM #{table}
            WHERE syllables BETWEEN $1 AND $2
            GROUP BY rhyme, final_word
          ) AS sub_table
          GROUP BY rhyme
          HAVING COUNT(rhyme) >= $3
        SQL
        sql[:la] = <<-SQL
          SELECT line, syllables, final_word, rhyme
          FROM #{table} WHERE rhyme = $1
        SQL
        sql[:las] = <<-SQL
          SELECT line, syllables, final_word, rhyme
          FROM #{table} WHERE rhyme = $1
          AND syllables BETWEEN $2 AND $3
        SQL
        sql
      end

      # Create the stored procedures in the database.
      def create_sprocs
        sprocs_sql_hash.each do |key, value|
          db.prepare key.to_s, value
        end
      rescue
        msg = "ERROR: Database table structure is invalid." +
            "\n       Please manually DROP the corrupt table and recreate it."
        raise Poefy::StructureInvalid.new(msg)
      end

      # Find rhymes and counts greater than a certain length.
      def sproc_rhymes_by_count rhyme_count
        rs = db.exec_prepared 'rbc', [rhyme_count]
        rs.values.map do |row|
          {
            'rhyme' => row[0],
            'count' => row[1].to_i
          }
        end
      end

      # Also adds syllable selection.
      def sproc_rhymes_by_count_syllables rhyme_count, syllable_min_max
        arg_array = [
          syllable_min_max[:min],
          syllable_min_max[:max],
          rhyme_count
        ]
        rs = db.exec_prepared 'rbcs', arg_array
        rs.values.map do |row|
          {
            'rhyme' => row[0],
            'count' => row[1].to_i
          }
        end
      end

      # Find all lines for a certain rhyme.
      def sproc_lines_by_rhyme rhyme
        rs = db.exec_prepared 'la', [rhyme]
        rs.values.map do |row|
          {
            'line'       => row[0],
            'syllables'  => row[1].to_i,
            'final_word' => row[2],
            'rhyme'      => row[3]
          }
        end
      end

      # Also adds syllable selection.
      def sproc_lines_by_rhyme_syllables rhyme, syllable_min_max
        arg_array = [
          rhyme,
          syllable_min_max[:min],
          syllable_min_max[:max]
        ]
        rs = db.exec_prepared 'las', arg_array
        rs.values.map do |row|
          {
            'line'       => row[0],
            'syllables'  => row[1].to_i,
            'final_word' => row[2],
            'rhyme'      => row[3]
          }
        end
      end

  end

end

################################################################################
