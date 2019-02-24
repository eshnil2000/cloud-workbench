# frozen_string_literal: true

require 'forwardable'
class MetricObservation
  attr_accessor(:provider_name, :provider_instance_id)
  attr_reader(:concrete_metric_observation)

  extend TimeHelper
  include ActiveModel::Model
  extend Forwardable

  # Delegate the common methods to the concrete implementation.
  def_delegators :@concrete_metric_observation, :time,
                                                :value,
                                                :virtual_machine_instance,
                                                :virtual_machine_instance_id,
                                                :metric_definition,
                                                :metric_definition_id

  # Persistence is implemented via concrete MetricObservations models e.g. NominalMetricObservation, OrderedMetricObservation
  # MUST return false in order to correctly display the form as otherwise an ActiveRecord id is required
  def persisted?
    false
  end

  def self.create!(params)
    vm_instance = identify_vm_instance(params)
    metric_definition = identify_metric_definition(params, vm_instance)
    metric_definition ||= create_default_metric_definition(params[:metric_definition_id], vm_instance.benchmark_execution.benchmark_definition)
    metric_definition.create_observation!(params[:time], params[:value], vm_instance.id)
  end

  TIME_COL = 0
  VALUE_COL = 1
  def self.import!(params)
    vm_instance = identify_vm_instance(params)
    metric_definition = identify_metric_definition(params, vm_instance)
    CSV.foreach(params[:file].path) do |row|
      metric_definition.create_observation!(row[TIME_COL], row[VALUE_COL], vm_instance.id)
    end
  end

  def self.identify_vm_instance(params)
    VirtualMachineInstance.where(provider_name: params[:provider_name],
                                 provider_instance_id: params[:provider_instance_id]).first
  end

  def self.identify_metric_definition(params, vm_instance)
    id_or_name = params[:metric_definition_id]
    first_definition_by_id(id_or_name) || first_definition_by_name(id_or_name, vm_instance)
  end

  def self.first_definition_by_id(id)
    MetricDefinition.where(id: id).first
  end

  def self.first_definition_by_name(name, vm_instance)
    benchmark = vm_instance.benchmark_execution.benchmark_definition
    MetricDefinition.where(benchmark_definition_id: benchmark.id, name: name).first
  end

  def self.create_default_metric_definition(name, benchmark_definition)
    MetricDefinition.create(benchmark_definition: benchmark_definition, name: name, unit: '', scale_type: :nominal)
  end

  # You MUST provide a metric_definition_id as argument
  def self.where(opts = {})
    metric_definition = MetricDefinition.find(opts[:metric_definition_id])
    if metric_definition.scale_type.nominal?
      NominalMetricObservation.where(opts)
    else
      OrderedMetricObservation.where(opts)
    end
  end

  # Assumes that all observations are from the same metric_definition
  def self.to_csv(metric_observations)
    metric_definition = metric_observations.first.metric_definition rescue nil
    CSV.generate do |csv|
      csv << ['Benchmark Start Time', 'Provider Name', 'Provider VM Id', 'VM Role', 'Time', "Value #{metric_definition.unit if metric_definition.present?}"]
      metric_observations.each do |metric_observation|
        vm = metric_observation.virtual_machine_instance
        csv << [formatted_time(vm.benchmark_execution.benchmark_start_time),
                vm.provider_name,
                vm.provider_instance_id,
                vm.role,
                metric_observation.time,
                metric_observation.value
               ]
      end
    end
  end

  # Note: This query is expensive
  def self.with_query_params(params)
    metric_definition_id = params[:metric_definition_id]
    fail 'Listing metric observations requires a <strong>metric_definition_id</strong> as parameter.' if params[:metric_definition_id].nil?
    metric_definition = MetricDefinition.find(metric_definition_id)
    fail "There exists no metric definition with the provided metric_definition_id #{metric_definition_id}" if metric_definition.nil?
    observations = self.where(metric_definition_id: metric_definition.id)

    # Filter by execution
    execution_id = params[:benchmark_execution_id]
    if execution_id.present?
      execution = BenchmarkExecution.find(execution_id)
      fail "There exists no benchmark_execution with the provided benchmark_execution_id #{metric_definition_id}" if execution.nil?
      observations = observations.where(virtual_machine_instance_id: VirtualMachineInstance.select('id').where(benchmark_execution_id: execution_id))
    end
    observations
  end
end
