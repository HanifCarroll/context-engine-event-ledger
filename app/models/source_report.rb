class SourceReport < ApplicationRecord
  self.primary_key = :id

  has_many :ingestion_batches, dependent: :restrict_with_exception
end
