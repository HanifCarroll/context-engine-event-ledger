class Entity < ApplicationRecord
  self.primary_key = :id

  has_many :entity_aliases, dependent: :delete_all
end
