# frozen_string_literal: true

class NominalMetricObservation < ApplicationRecord
  belongs_to :metric_definition
  validates :metric_definition_id, presence: true
  belongs_to :virtual_machine_instance
end
