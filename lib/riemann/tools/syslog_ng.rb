# frozen_string_literal: true

require 'strscan'

require 'riemann/tools'

module Riemann
  module Tools
    class SyslogNg
      include Riemann::Tools

      opt :socket, 'Path to syslog-ng socket', short: :none, type: :string, default: '/var/lib/syslog-ng/syslog-ng.ctl'
      opt :format, 'Format for service name', short: :none, type: :string, default: '%<source_name>s;%<source_id>s;%<source_instance>s;%<state>s;%<type>s'

      opt :source_name, 'Filter on SourceName', short: :none, type: :strings
      opt :source_id, 'Filter on SourceId', short: :none, type: :strings
      opt :source_instance, 'Filter on SourceInstance', short: :none, type: :strings
      opt :state, 'Filter on State', short: :none, type: :strings
      opt :type, 'Filter on Type', short: :none, type: :strings

      opt :queued_warning, 'Queued messages warning threshold', short: :none, default: 300
      opt :queued_critical, 'Queued messages critical threshold', short: :none, default: 1000

      def initialize
        @socket = UNIXSocket.new(opts[:socket])
      end

      def tick
        statistics.each do |statistic|
          report({
                   service: format(opts[:format], statistic),
                   metric: statistic[:metric],
                   state: statistic_state(statistic[:type], statistic[:metric]),
                 })
        end
      end

      def statistics
        res = []

        @socket.puts 'STATS CSV'
        @socket.gets # discard header
        while (line = @socket.gets.chomp) != '.'
          source_name, source_id, source_instance, state, type, metric = line.split(';')

          next if rejected_source_name?(source_name)
          next if rejected_source_id?(source_id)
          next if rejected_source_instance?(source_instance)
          next if rejected_state?(state)
          next if rejected_type?(type)

          res << {
            source_name: source_name,
            source_id: source_id,
            source_instance: source_instance,
            state: state,
            type: type,
            metric: metric.to_f,
          }
        end

        res
      end

      def rejected_source_name?(source_name)
        opts[:source_name] && !opts[:source_name].include?(source_name)
      end

      def rejected_source_id?(source_id)
        opts[:source_id] && !opts[:source_id].include?(source_id)
      end

      def rejected_source_instance?(source_instance)
        opts[:source_instance] && !opts[:source_instance].include?(source_instance)
      end

      def rejected_state?(state)
        opts[:state] && !opts[:state].include?(state)
      end

      def rejected_type?(type)
        opts[:type] && !opts[:type].include?(type)
      end

      def statistic_state(type, metric)
        if type == 'dropped'
          dropped_statistic_state(metric)
        elsif type == 'queued'
          queued_statistic_state(metric)
        end
      end

      def dropped_statistic_state(metric)
        metric == 0.0 ? 'ok' : 'critical'
      end

      def queued_statistic_state(metric)
        if metric >= opts[:queued_critical]
          'critical'
        elsif metric >= opts[:queued_warning]
          'warning'
        else
          'ok'
        end
      end
    end
  end
end
