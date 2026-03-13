# frozen_string_literal: true

require 'legion/extensions/consent/version'
require 'legion/extensions/consent/helpers/tiers'
require 'legion/extensions/consent/helpers/consent_map'
require 'legion/extensions/consent/runners/consent'

module Legion
  module Extensions
    module Consent
      extend Legion::Extensions::Core if Legion::Extensions.const_defined? :Core
    end
  end
end
