class BrandConfig < ActiveRecord::Base
  include BrandableCSS

  self.primary_key = 'md5'
  serialize :variables, Hash

  attr_accessible :variables

  validates :variables, presence: true
  validates :md5, length: {is: 32}

  before_validation :generate_md5
  before_update do
    raise 'BrandConfigs are a key-value mapping of config variables and an md5 digest '\
          'of those variables, so they are immutable. You do not update them, you just '\
          'save a new one and it will generate the new md5 for you'
  end

  has_many :accounts, foreign_key: 'brand_config_md5'

  def generate_md5
    self.id = Digest::MD5.hexdigest(self.variables.to_s)
  end

  def get_value(variable_name)
    self.variables[variable_name]
  end

  def to_scss
    "// This file is autogenerated by brand_config.rb as a result of running `rake brand_configs:write`\n" +
    variables.map do |name, value|
      next unless (config = BrandableCSS.variables_map[name])
      value = %{url("#{value}")} if config['type'] == 'image'
      "$#{name}: #{value};"
    end.compact.join("\n")
  end

  def scss_file
    scss_dir.join('_brand_variables.scss')
  end

  def scss_dir
    BrandableCSS.branded_scss_folder.join(md5)
  end

  def public_folder
    "dist/brandable_css/#{md5}"
  end

  def save_scss_file!
    logger.info "saving brand variables file: #{scss_file}"
    scss_dir.mkpath
    scss_file.write(to_scss)
  end

  def remove_scss_file!
    return unless scss_dir.exist?
    logger.info "removing: #{scss_dir}"
    scss_dir.rmtree
  end

  def compile_css!
    BrandableCSS.compile_brand!(md5)
  end

  def sync_to_s3!(&block)
    Canvas::CDN.push_to_s3!(public_folder, &block) if Canvas::CDN.enabled?
  end

  def save_and_sync_to_s3!(progress=nil)
    progress.update_completion!(5) if progress
    save_scss_file!
    progress.update_completion!(10) if progress
    compile_css!
    progress.update_completion!(50) if progress
    sync_to_s3! do |percent_complete|
      # send at most 1 UPDATE query per second
      if progress && (progress.updated_at < 1.second.ago)
        total_percent = 50 + percent_complete / 2
        # This callback is called within a Parallel.each thread so
        # we need to explicitly tell it to use the existing connection.
        Progress.connection_pool.with_connection do
          progress.update_completion!(total_percent)
        end
      end
    end
  end

  def self.destroy_if_unused(md5)
    return unless md5
    unused_brand_config = BrandConfig.
      where(md5: md5).
      where("NOT EXISTS (?)", Account.where("brand_config_md5=brand_configs.md5")).
      where("NOT share").
      first
    if unused_brand_config
      unused_brand_config.destroy
      unused_brand_config.remove_scss_file!
    end
  end

  def self.clean_unused_from_db!
    BrandConfig.
      where("NOT EXISTS (?)", Account.where("brand_config_md5=brand_configs.md5")).
      where('NOT share').
      # When someone is actively working in the theme editor, it just saves one
      # in their session, so only delete stuff that is more than a week old,
      # to not clear out a theme someone was working on.
      where(["created_at < ?", 1.week.ago]).
      delete_all
  end

end
