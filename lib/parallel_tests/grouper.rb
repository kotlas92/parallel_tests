module ParallelTests
  class Grouper
    class << self
      def by_steps(tests, num_groups, options)
        features_with_steps = build_features_with_steps(tests, options)
        in_even_groups_by_size(features_with_steps, num_groups)
      end

      def by_scenarios(tests, num_groups, options={})
        scenarios = group_by_scenarios(tests, options)
        in_even_groups_by_size(scenarios, num_groups)
      end

      def in_even_groups_by_size(items, num_groups, options= {})
        groups = Array.new(num_groups) { {:items => [], :size => 0} }

        # add all files that should run in a single process to one group
        (options[:single_process] || []).each do |pattern|
          matched, items = items.partition { |item, _size| item =~ pattern }
          matched.each { |item, size| add_to_group(groups.first, item, size) }
        end

        groups_to_fill = (options[:isolate] ? groups[1..-1] : groups)
        group_features_by_size(items_to_group(items), groups_to_fill)

        # add all other files
        largest_first(items).each do |item, size|
          smallest = smallest_group(groups_to_fill)
          add_to_group(smallest, item, size)
        end

        report_features_balancing(groups)

        groups.map!{|g| g[:items].sort }

        groups
      end

      def by_weight(tests, num_groups, options)
        features_with_steps = build_features_with_weight(tests, options)
        in_even_groups_by_size(features_with_steps, num_groups)
      end

      private

      def largest_first(files)
        files.sort_by{|_item, size| size }.reverse
      end

      def smallest_group(groups)
        groups.min_by { |g| g[:size] }
      end

      def add_to_group(group, item, size)
        group[:items] << item
        group[:size] += size
      end

      def build_features_with_steps(tests, options)
        require 'gherkin/parser'
        ignore_tag_pattern = options[:ignore_tag_pattern].nil? ? nil : Regexp.compile(options[:ignore_tag_pattern])
        parser = ::Gherkin::Parser.new
        # format of hash will be FILENAME => NUM_STEPS
        steps_per_file = tests.each_with_object({}) do |file,steps|
          feature = parser.parse(File.read(file)).fetch(:feature)

          # skip feature if it matches tag regex
          next if feature[:tags].grep(ignore_tag_pattern).any?

          # count the number of steps in the file
          # will only include a feature if the regex does not match
          all_steps = feature[:children].map{|a| a[:steps].count if a[:tags].grep(ignore_tag_pattern).empty? }.compact
          steps[file] = all_steps.inject(0,:+)
        end
        steps_per_file.sort_by { |_, value| -value }
      end

      def group_by_scenarios(tests, options={})
        require 'parallel_tests/cucumber/scenarios'
        ParallelTests::Cucumber::Scenarios.all(tests, options)
      end

      def group_features_by_size(items, groups_to_fill)
        items.each do |item, size|
          size ||= 1
          smallest = smallest_group(groups_to_fill)
          add_to_group(smallest, item, size)
        end
      end

      def items_to_group(items)
        items.first && items.first.size == 2 ? largest_first(items) : items
      end

      def build_features_with_weight(tests, options)
        result = []

        tests.each do |file|
          file_content = []
          File.open(file).read.each_line{|line| file_content << line}
          if file_content.first[/weight ([0-9]+)/]
            weight = $1.to_i
          else
            weight = 1
          end
          result << [file, weight]
        end

        result
      end

      def report_features_balancing(groups)
        $stdout.puts '='*20
        $stdout.puts "Grouping features:\n"
        groups.each_with_index do |group, index|
          $stdout.puts "Group number #{index}"
          $stdout.puts group[:items].join("\n")
          $stdout.puts "Total weight: #{group[:size]}"
          $stdout.puts '-'*20
        end
        $stdout.puts '='*20
        $stdout.flush
      end
    end
  end
end
