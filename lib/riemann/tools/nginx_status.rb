# frozen_string_literal: true

require 'riemann/tools'

# Gathers nginx status stub statistics and submits them to Riemann.
# See http://wiki.nginx.org/HttpStubStatusModule for configuring Nginx appropriately
module Riemann
  module Tools
    class NginxStatus
      include Riemann::Tools
      require 'net/http'
      require 'uri'

      opt :uri, 'Nginx Stub Status URI', default: 'http://localhost:8080/nginx_status'
      opt :checks, 'Which metrics to report.', type: :strings,
                                               default: %w[active accepted handled requests reading writing waiting]
      opt :active_warning, 'Active connections warning threshold', default: 0
      opt :active_critical, 'Active connections critical threshold', default: 0
      opt :reading_warning, 'Reading connections warning threshold', default: 0
      opt :reading_critical, 'Reading connections critical threshold', default: 0
      opt :writing_warning, 'Writing connections warning threshold', default: 0
      opt :writing_critical, 'Writing connections critical threshold', default: 0
      opt :waiting_warning, 'Waiting connections warning threshold', default: 0
      opt :waiting_critical, 'Waiting connections critical threshold', default: 0

      def initialize
        @uri = URI.parse(opts[:uri])

        # sample response:
        #
        # Active connections: 1
        # server accepts handled requests
        #  39 39 39
        # Reading: 0 Writing: 1 Waiting: 0
        @keys = %w[active accepted handled requests reading writing waiting]
        @re = /Active connections: (\d+) \n.+\n (\d+) (\d+) (\d+) \nReading: (\d+) Writing: (\d+) Waiting: (\d+)/m
      end

      def state(key, value)
        if opts.key? "#{key}_critical".to_sym
          critical_threshold = opts["#{key}_critical".to_sym]
          return 'critical' if critical_threshold.positive? && (value >= critical_threshold)
        end

        if opts.key? "#{key}_warning".to_sym
          warning_threshold = opts["#{key}_warning".to_sym]
          return 'warning' if warning_threshold.positive? && (value >= warning_threshold)
        end

        'ok'
      end

      def tick
        response = nil
        begin
          response = ::Net::HTTP.get(@uri)
        rescue StandardError => e
          report(
            service: 'nginx health',
            state: 'critical',
            description: "Connection error: #{e.class} - #{e.message}",
          )
        end

        return if response.nil?

        report(
          service: 'nginx health',
          state: 'ok',
          description: 'Nginx status connection ok',
        )

        values = @re.match(response).to_a[1, 7].map(&:to_i)

        @keys.zip(values).each do |key, value|
          report({
                   service: "nginx #{key}",
                   metric: value,
                   state: state(key, value),
                   tags: ['nginx'],
                 })
        end
      end
    end
  end
end
