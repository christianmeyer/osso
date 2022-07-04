# frozen_string_literal: true

require 'dotenv/load' unless ENV['RACK_ENV']

require './app'
require 'osso'
require 'sinatra/activerecord/rake'
require 'mail'
require 'mail-ses'

if ENV['RACK_ENV'] == 'production'
  Mail.defaults do
    case ENV['MAIL_METHOD'].to_s.downcase
    when 'ses'
      delivery_method Mail::SES, {
        region: ENV['SES_REGION'],
        use_iam_profile: true,
        mail_options: ENV['SES_IDENTITY_ARN'] ? {
          from_email_address_identity_arn: ENV['SES_IDENTITY_ARN']
        } : nil
      }
    else
      delivery_method :smtp, {
        port: ENV['SMTP_PORT'],
        address: ENV['SMTP_SERVER'],
        user_name: ENV['SMTP_LOGIN'],
        password: ENV['SMTP_PASSWORD'],
        domain: (ENV['SMTP_DOMAIN']).to_s,
        authentication: :plain,
      }
    end
  end
end

osso = Gem::Specification.find_by_name('osso')
osso_rakefile = "#{osso.gem_dir}/lib/osso/Rakefile"
load osso_rakefile

Dir.glob("#{osso.gem_dir}/lib/tasks/*.rake").each { |r| load r }
Dir.glob('lib/tasks/*.rake').each { |r| load r }
