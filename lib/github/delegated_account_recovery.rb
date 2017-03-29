# frozen_string_literal: true

require "bindata"
require "openssl"

require_relative "delegated_account_recovery/constants"
require_relative "delegated_account_recovery/recovery_token"
require_relative "delegated_account_recovery/encrypted_data"
require_relative "delegated_account_recovery/crypto_helper"
require_relative "delegated_account_recovery/provider"
require_relative "delegated_account_recovery/account_provider"
require_relative "delegated_account_recovery/recovery_provider"
require_relative "delegated_account_recovery/serialization/encrypted_data_reader"
require_relative "delegated_account_recovery/serialization/encrypted_data_writer"
require_relative "delegated_account_recovery/serialization/recovery_token_writer"
require_relative "delegated_account_recovery/serialization/recovery_token_reader"

module GitHub
  module DelegatedAccountRecovery
    # Represents a binary serialization error
    class RecoveryTokenSerializationError < StandardError; end

    # Represents invalid data within a valid token
    #  (e.g. wrong `version` number, invalid token `type`)
    class TokenFormatError < StandardError; end

    # Represents all crypto errors
    #   (e.g. invalid keys, invalid signature, decrypt failures)
    class CryptoError < StandardError; end

    # Represents providers supplying invalid configurations
    #  (e.g. non-https URLs, missing required fields, http errors)
    class ProviderConfigError < StandardError; end

    # Represents an invalid countersigned recovery token.
    #  (e.g. invalid signature, invalid nested token, unregistered provider, stale tokens)
    class CountersignedTokenError < StandardError
      attr_reader :key
      def initialize(message, key)
        super(message)
        @key = key
      end
    end

    # Represents an invalid recovery token.
    #  (e.g. invalid signature, unregistered provider, stale tokens)
    class RecoveryTokenError < StandardError; end

    # Represents a call to to `recovery_provider` or `account_provider` that
    # has not been registered.
    class UnknownProviderError < ArgumentError; end

    include Constants

    class << self
      # recovery provider data is only loaded (and cached) upon use.
      attr_accessor :recovery_providers, :account_providers, :cache, :allow_unsafe_urls,
        :privacy_policy, :icon_152px, :authority

      # Find and load remote recovery provider configuration data.
      #
      # provider_origin: the origin that contains the config data in a well-known
      # location.
      def recovery_provider(provider_origin)
        unless self.recovery_providers
          raise "No recovery providers configured"
        end
        if self.recovery_providers.include?(provider_origin)
          RecoveryProvider.new(provider_origin).load
        else
          raise UnknownProviderError, "Unknown recovery provider: #{provider_origin}"
        end
      end

      # Permit an origin to act as a recovery provider.
      #
      # provider_origin: the origin to permit
      def register_recovery_provider(provider_origin)
        self.recovery_providers ||= []
        self.recovery_providers << provider_origin
      end

      # Find and load remote account provider configuration data.
      #
      # provider_origin: the origin that contains the config data in a well-known
      # location.
      def account_provider(provider_origin)
        unless self.account_providers
          raise "No account providers configured"
        end
        if self.account_providers.include?(provider_origin)
          AccountProvider.new(provider_origin).load
        else
          raise UnknownProviderError, "Unknown account provider: #{provider_origin}"
        end
      end

      # Permit an origin to act as an account provider.
      #
      # account_origin: the origin to permit
      def register_account_provider(account_origin)
        self.account_providers ||= []
        self.account_providers << account_origin
      end

      # Provide a reference to the account provider configuration for this web app
      def this_account_provider
        AccountProvider.this
      end

      # Provide a reference to the recovery provider configuration for this web app
      def this_recovery_provider
        RecoveryProvider.this
      end

      # Returns a hash of all configuration values, recovery and account provider.
      def account_and_recovery_provider_config
        provider_data = Darrrr.this_account_provider.try(:to_h) || {}

        if Darrrr.this_recovery_provider
          provider_data.merge!(recovery_provider_config) do |key, lhs, rhs|
            unless lhs == rhs
              raise ArgumentError, "inconsistent config value detected #{key}: #{lhs} != #{rhs}"
            end

            lhs
          end
        end

        provider_data
      end

      def account_provider_config
        this_account_provider.to_h
      end

      def recovery_provider_config
        this_recovery_provider.to_h
      end
    end
  end
end