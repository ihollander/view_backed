require 'view_backed/column_rails_4'
require 'view_backed/column_rails_5'
require 'view_backed/view_definition'
require 'view_backed/rails_5'
require 'view_backed/max_refresh_wait_time_exceeded_error'
require 'view_backed/materialized_view'

module ViewBacked
  extend ActiveSupport::Concern

  def read_only?
    true
  end

  def self.options
    @options ||= { max_refresh_wait_time: nil }
  end

  class_methods do
    delegate :columns, to: :view_definition
    prepend ViewBacked::Rails5 if Rails.version.match(/^5/)

    def materialized(_materialized = false)
      @materialized ||= _materialized
    end

    def refresh!
      raise 'cannot refresh an unmaterialized view' unless materialized
      with_materialized_view do |materialized_view|
        materialized_view.ensure_current!
        materialized_view.refresh!
      end
    end

    def view
      yield view_definition

      default_scope do
        if materialized
          ensure_current_data!
          all
        else
          from "(#{view_definition.scope.to_sql}) AS #{table_name}"
        end
      end
    end

    def view_definition
      @view_definition ||= ViewDefinition.new(table_name)
    end

    def ensure_current_data!
      with_materialized_view do |materialized_view|
        materialized_view.ensure_current!
        materialized_view.wait_until_populated
      end
    end

    private

    def materialized?
      materialized
    end

    def with_materialized_view
      yield MaterializedView.new(
        name: table_name,
        sql: view_definition.scope.to_sql,
        indexed_column_names: view_definition.indexed_column_names
      )
    end
  end
end
