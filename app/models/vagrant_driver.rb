# frozen_string_literal: true

require 'pathname'
# Vagrant commands can be further refactored into its own method and
# generic access can be provided to commands ands its corresponding logs.
class VagrantDriver
  include ShellRunner
  attr_reader :vagrantfile_path, :vagrant_dir_path
  CURRENT_DIR = '.'
  PARENT_DIR = '..'

  def initialize(vagrantfile_path, log_dir)
    @vagrantfile_path = vagrantfile_path
    @vagrant_dir_path = File.dirname(vagrantfile_path)
    @log_dir = log_dir
  end

  # Returns an array of hashes
  # Example: [ { provider_name: 'aws', provider_instance_id: 'i-cn539k8x', role: 'default' }, ... ]
  def detect_vm_instances
    virtual_machines = []
    Pathname(machines_dir).each_child do |machine|
      if candiate_vms_role(machine)
        virtual_machines.concat(detect_vms_with_role(role(machine)))
      end
    end
    virtual_machines
  end

  # The meta directories "." and ".." shouln't be detected as roles
  def meta_directory?(role)
    role == CURRENT_DIR ||
    role == PARENT_DIR
  end

  def role(machine)
    machine.basename.to_s
  end

  def detect_vms_with_role(role)
    Rails.application.config.supported_providers.collect do |provider|
      provider_id_file = File.join(machines_dir, role, provider, 'id')
      if File.exist?(provider_id_file)
        provider_id = File.read(provider_id_file)
        { provider_name: provider, provider_instance_id: provider_id, role: role }
      end
    end.compact # Clean up nil values in array in case of multiple providers
  end

  def up(provider)
    shell("vagrant up --provider=#{provider}", dir: @vagrant_dir_path, log: up_log_file)
  end

  def reprovision
    # NOTE: Use Vagrant up log file that gets displayed as workaround
    shell('vagrant provision', dir: @vagrant_dir_path, log: up_log_file)
  end

  def destroy
    shell('vagrant destroy --force', dir: @vagrant_dir_path, log: destroy_log_file)
  end

  def up_log
    File.read(up_log_file) rescue ''
  end

  def reprovision_log
    File.read(reprovision_log_file) rescue ''
  end

  def destroy_log
    File.read(destroy_log_file) rescue ''
  end

  def up_log_file
    File.join(@log_dir, 'vagrant_up.log')
  end

  def reprovision_log_file
    File.join(@log_dir, 'vagrant_reprovision.log')
  end

  def destroy_log_file
    File.join(@log_dir, 'vagrant_destroy.log')
  end

  private

    def candiate_vms_role(machine)
      machine.directory? && !meta_directory?(role(machine))
    end

    def machines_dir
      File.join(@vagrant_dir_path, '.vagrant', 'machines')
    end
end
