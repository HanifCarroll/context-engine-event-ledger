module ContextLedger
  class Projector
    NAME = "core-v1"

    def apply(event)
      data = event.data
      event_id = event.event_id
      logical_type = data.fetch("type")

      case logical_type
      when "context.entity_registered.v1"
        Entity.create!(
          id: data.dig("data", "id"),
          kind: data.dig("data", "kind"),
          display_name: data.dig("data", "display_name"),
          privacy: data.fetch("privacy"),
          status: "active",
          created_by_event_id: event_id,
          updated_by_event_id: event_id
        )
      when "context.entity_alias_added.v1"
        add_alias(data, event_id)
      when "context.entity_renamed.v1"
        entity = Entity.find(data.dig("data", "id"))
        entity.update!(display_name: data.dig("data", "display_name"), updated_by_event_id: event_id)
      when "context.entity_merged.v1"
        source = Entity.find(data.dig("data", "source_id"))
        target = Entity.find(data.dig("data", "target_id"))
        raise Error.new("entity_merge_invalid", "An entity cannot merge into itself") if source.id == target.id
        source.update!(status: "merged", merged_into_id: target.id, updated_by_event_id: event_id)
      when "context.entity_retired.v1"
        entity = Entity.find(data.dig("data", "id"))
        entity.update!(status: "retired", updated_by_event_id: event_id)
      when "ledger.assertion_status_changed.v1"
        state = EventEffectiveState.find(data.dig("data", "event_id"))
        state.update!(assertion_status: data.dig("data", "assertion_status"), updated_by_event_id: event_id)
      when "ledger.event_corrected.v1"
        state = EventEffectiveState.find(data.dig("data", "event_id"))
        state.update!(correction_status: "corrected", replacement_event_id: data.dig("data", "replacement_event_id"), updated_by_event_id: event_id)
      when "ledger.event_retracted.v1"
        state = EventEffectiveState.find(data.dig("data", "event_id"))
        state.update!(correction_status: "retracted", updated_by_event_id: event_id)
      end

      data.fetch("entity_roles").each do |role|
        EventEntityRole.create!(
          event_id: event_id,
          entity_id: role.fetch("entity_id"),
          role: role.fetch("role"),
          ordinal: role.fetch("ordinal")
        )
      end

      EventEffectiveState.find_or_create_by!(event_id: event_id) do |state|
        state.assertion_status = data.fetch("assertion_status")
        state.correction_status = "effective"
        state.updated_by_event_id = event_id
      end

      position = Rails.configuration.event_store.read.stream("Ledger$all").count - 1
      ProjectionCheckpoint.upsert(
        {
          projection_name: NAME,
          ledger_position: position,
          event_id: event_id,
          updated_at: Time.now.utc
        },
        unique_by: :projection_name
      )
    end

    def rebuild!
      EntityAlias.delete_all
      EventEntityRole.delete_all
      EventEffectiveState.delete_all
      Entity.delete_all
      ProjectionCheckpoint.delete_all
      Rails.configuration.event_store.read.stream("Ledger$all").each { |event| apply(event) }
      { "projection" => NAME, "events_applied" => Rails.configuration.event_store.read.stream("Ledger$all").count }
    end

    private

    def add_alias(data, event_id)
      entity = Entity.find(data.dig("data", "id"))
      alias_name = data.dig("data", "alias")
      EntityAlias.create!(
        entity_id: entity.id,
        alias_name: alias_name,
        normalized_alias: alias_name.unicode_normalize(:nfkc).downcase.strip,
        created_by_event_id: event_id
      )
    end
  end
end
