# frozen_string_literal: true

require_relative 'lib/legion/extensions/consent/version'

Gem::Specification.new do |spec|
  spec.name          = 'lex-consent'
  spec.version       = Legion::Extensions::Consent::VERSION
  spec.authors       = ['Esity']
  spec.email         = ['matthewdiverson@gmail.com']

  spec.summary       = 'LEX Consent'
  spec.description   = 'Four-tier consent gradient with earned autonomy for brain-modeled agentic AI'
  spec.homepage      = 'https://github.com/LegionIO/lex-consent'
  spec.license       = 'MIT'
  spec.required_ruby_version = '>= 3.4'

  spec.metadata['homepage_uri'] = spec.homepage
  spec.metadata['source_code_uri'] = 'https://github.com/LegionIO/lex-consent'
  spec.metadata['documentation_uri'] = 'https://github.com/LegionIO/lex-consent'
  spec.metadata['changelog_uri'] = 'https://github.com/LegionIO/lex-consent'
  spec.metadata['bug_tracker_uri'] = 'https://github.com/LegionIO/lex-consent/issues'
  spec.metadata['rubygems_mfa_required'] = 'true'

  spec.files = Dir.chdir(File.expand_path(__dir__)) do
    Dir.glob('{lib,spec}/**/*') + %w[lex-consent.gemspec Gemfile]
  end
  spec.require_paths = ['lib']
  spec.add_development_dependency 'sequel', '>= 5.70'
  spec.add_development_dependency 'sqlite3', '>= 2.0'
end
