module BuildKit
  
  require 'rmagick'
  require 'json'

  module Tasks

    def self.decorate_icon runner, task_opts
      task = DecorateIconTask.new({ runner: runner, opts: task_opts })
      task.run!
    end

    private

    class DecorateIconTask < BuildKitTask

      attr_reader :decorated_icons

      def initialize(attributes = {})
        super
        @decorated_icons = []
      end

      def run!
        @runner.store[:backup_icon_paths] = []
        decorate_icons!
        complete_task!
      end

      private

      def assert_requirements
        BuildKit::Utilities::Assertions.assert_required_config [:info_plist, :icon_dir], @runner
        BuildKit::Utilities::Assertions.assert_files_exist [@config.info_plist, @config.icon_dir]
      end

      def is_asset_catalog
        File.exist? "#{@config.icon_dir}/Contents.json"
      end

      def version_number_to_draw
        if @runner.has_completed_task? :increment_version
          @runner.store[:new_version_number][:full]
        else
          BuildKit::Utilities::VersionNumber.plist_version_number(runner.config.info_plist)[:full]
        end
      end

      def icon_files_to_decorate_asset_catalog
        to_decorate = []
        contents = JSON.parse File.read("#{@config.icon_dir}/Contents.json")
        contents["images"].each do |image|
          filename = image["filename"]
          next unless filename
          to_decorate << "#{@config.icon_dir}/#{filename}"
        end
        to_decorate
      end

      def icon_files_to_decorate_CFBundleIcons
        to_decorate = []
        Dir.glob("#{@config.icon_dir}/*.png").each do |filename|
          to_decorate << filename
        end
        to_decorate
      end

      def icon_files_to_decorate
        return is_asset_catalog ? icon_files_to_decorate_asset_catalog : icon_files_to_decorate_CFBundleIcons
      end

      def backup_icon! icon_path
        backup_icon_filename = "_Original-" + File.basename(icon_path)
        backup_icon_path = File.join File.dirname(icon_path), backup_icon_filename
        FileUtils.mv icon_path, backup_icon_path, :force => true
        @runner.store[:backup_icon_paths] << backup_icon_path
      end

      def decorate_icons!
        icon_files_to_decorate.each do |img_path|
          @decorated_icons << create_decorated_version_of(img_path)
        end
      end

      def create_decorated_version_of icon_path
        original = Magick::ImageList.new icon_path
        decorated_icon = original.copy
        icon_dimension = original.rows

        background = Magick::Draw.new
        background.fill_opacity(0.75)
        background.rectangle(0, icon_dimension - (icon_dimension * 0.225), icon_dimension, icon_dimension)
        background.draw decorated_icon

        annotation_params = {
          gravity: Magick::SouthGravity, 
          pointsize: icon_dimension * 0.11 , 
          stroke: 'transparent', 
          fill: '#FFF', 
          font_family: "Helvetica CY", 
          font_weight: Magick::BoldWeight 
        }

        version_text = Magick::Draw.new
        version_text.annotate(decorated_icon, 0, 0, 0, icon_dimension * 0.05  , "#{version_number_to_draw}") do
          self.gravity = annotation_params[:gravity]
          self.pointsize = annotation_params[:pointsize]
          self.stroke = annotation_params[:stroke]
          self.fill = annotation_params[:fill]
          self.font_family = annotation_params[:font_family]
          self.font_weight = annotation_params[:font_weight]
        end

        backup_icon! icon_path
        decorated_icon.write(icon_path)

        icon_path
      end

      def complete_task!
        message = "Icons have been decorated with #{version_number_to_draw}. They are here: \n" + @decorated_icons.join(",\n     ")
        @runner.task_completed! :decorate_icon, message, message 
      end

    end

  end
        
end
