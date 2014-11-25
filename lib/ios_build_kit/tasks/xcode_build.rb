module BuildKit

  module Tasks

    require "fileutils"

    def self.xcode_build runner, task_opts
      task = XcodeBuildTask.new({ runner: runner, opts: task_opts })
      task.run!
    end

    private

    class XcodeBuildTask < BuildKitTask

      attr_reader :output

      def run!
        run_command! "clean" if @task_options[:clean]
        run_command! "build"
        create_build_directory unless File.exists?(@config.absolute_build_dir)
        cleanup_build_assets!
        complete_task!
      end

      private

      def assert_requirements
        BuildKit::Utilities::Assertions.assert_required_config [:app_name, :workspace, :sdk, :build_configuration, :build_dir, :scheme, :code_sign, :provisioning_profile], @runner
        BuildKit::Utilities::Assertions.assert_files_exist [@config.absolute_build_dir, @config.workspace]
      end

      def create_build_directory
        FileUtils.mkdir_p(@config.absolute_build_dir)
      end

      def build_command cmd
        workspace_arg = "-workspace \"#{@config.workspace}\""
        sdk_arg = "-sdk \"#{@config.sdk}\""
        scheme_arg = "-scheme \"#{@config.scheme}\""   
        configuration_arg = "-configuration \"#{@config.build_configuration}\""
        code_sign_arg = "CODE_SIGN_IDENTITY=\"#{@config.code_sign}\""
        provisioning_arg = "PROVISIONING_PROFILE=\"#{@config.provisioning_profile}\""
        build_dir_arg = "CONFIGURATION_BUILD_DIR=\"#{@config.absolute_build_dir}\""
        "xcodebuild #{workspace_arg} #{sdk_arg} #{scheme_arg} #{configuration_arg} #{code_sign_arg} #{provisioning_arg} #{build_dir_arg} #{cmd} | xcpretty -c; echo EXIT CODE: ${PIPESTATUS}"
      end

      def run_command! cmd
        command = build_command cmd
        cmd_output = %x[#{command}]
        @output = cmd_output if is_build? cmd
        puts cmd_output if @task_options[:log]
      end

      def is_build? cmd
        cmd == "build"
      end

      def build_succeeded?
        @output.include? "EXIT CODE: 0"
      end

      def cleanup_build_assets!
        if @runner.has_completed_task? :decorate_icon
          @runner.store[:backup_icon_paths].each do |backup_icon_path|
            icon_path = backup_icon_path.gsub("_Original-", "")
            FileUtils.mv backup_icon_path, icon_path, :force => true
          end
        end
      end

      def complete_task!
        @runner.store[:xcode_build_succeeded] = build_succeeded?
        message = (build_succeeded?) ? "xcode_build completed, project built successfully" : "xcode_build completed, but the project failed to build"
        @runner.task_completed! :xcode_build, message, @output 
      end

    end

  end

end
