require "ruby_event_store/active_record/event"

Rails.configuration.event_store = RailsEventStore::Client.new
