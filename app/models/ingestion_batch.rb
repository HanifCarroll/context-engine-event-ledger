class IngestionBatch < ApplicationRecord
  self.primary_key = :id

  belongs_to :source_report
end
