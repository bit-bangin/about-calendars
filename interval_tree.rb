{
  title: "Collective Scheduling Utility",
  
  # Basic connector configuration without external dependencies
  connection: {
    fields: [
      {
        name: 'rate_limit',
        label: 'Rate Limit',
        type: 'integer',
        optional: true,
        default: 100,
        hint: 'Maximum number of API calls per hour.'
      }
    ],
    authorization: { type: 'none' },
    base_uri: ->() { 'dummy_uri' }
  },

  test: ->(connection) {
    {
      success: true,
      message: 'Successfully connected to scheduling service.'
    }
  },

  pick_lists: {
    timezone_list: -> {
      [
        ['Eastern Time (US & Canada)', 'America/New_York'],
        ['Central Time (US & Canada)', 'America/Chicago'],
        ['Mountain Time (US & Canada)', 'America/Denver'],
        ['Pacific Time (US & Canada)', 'America/Los_Angeles']
      ]
    }
  },

  object_definitions: {
  },

  methods: {
    # Centralized error handler
    error_handler: ->(args) {
      message = args[:message]
      details = args[:details] || {}

      # Log the error
      call(:log_error, { error: message, details: details })

      # Raise the Workato error
      error(message)
    },

    log_error: ->(args) {
      puts({ error: args[:error], details: args[:details] }.to_json)
    },

    # Logger for all types of logs
    logger: ->(args) {
      log_message = {
        level: args[:level].upcase,
        timestamp: Time.now.utc.iso8601,
        message: args[:message],
        context: args[:context] || {}
      }
      puts log_message.to_json
    },

      puts log_message.to_json
    },

    # Creates a new node for the interval tree
    create_node: ->(args) {
      center = args[:center]
      {
        center: center,
        intervals: [],
        left: nil,
        right: nil,
        height: 1
      }
    },

    # Gets height of a node, handling nil nodes
    node_height: ->(args) {
      node = args[:node]
      node ? node['height'] : 0
    },

    # Updates node height based on its children
    update_height: ->(args) {
      node = args[:node]
      if node
        node['height'] = 1 + [
          call(:node_height, { node: node['left'] }),
          call(:node_height, { node: node['right'] })
        ].max
      end
      node
    },
    
    # Calculates balance factor for AVL tree
    balance_factor: ->(connection, node) {
        # positive = right heavy, negative = left heavy
        call(:node_height, connection, node['right']) - call(:node_height, connection, node['left'])
    },

    # Performs left rotation for AVL tree balancing
    rotate_left: ->(connection, node) {
        # Used when right subtree becomes too heavy
        if node['right']
            new_root = node['right']
            node['right'] = new_root['left']
            new_root['left'] = node
        
            call(:update_height, connection, node)
            call(:update_height, connection, new_root)
            new_root
        else
            node
        end
    },

    # Performs right rotation for AVL tree balancing
    rotate_right: ->(connection, node) {
        # Used when left subtree becomes too heavy
        if node['left']
            new_root = node['left']
            node['left'] = new_root['right']
            new_root['right'] = node
            
            call(:update_height, connection, node)
            call(:update_height, connection, new_root)
            new_root
        else
            node
        end
    },

    # Balances a node in the AVL tree
    balance_node: ->(args) {
      node = args[:node]
      if node
        balance = call(:balance_factor, { node: node })

        if balance < -1
          if call(:balance_factor, { node: node['left'] }) > 0
            node['left'] = call(:rotate_left, { node: node['left'] })
          end
          node = call(:rotate_right, { node: node })
        elsif balance > 1
          if call(:balance_factor, { node: node['right'] }) < 0
            node['right'] = call(:rotate_right, { node: node['right'] })
          end
          node = call(:rotate_left, { node: node })
        end
      end
      node
    },

    # Builds a balanced interval tree from a list of intervals
    build_interval_tree: ->(args) {
      intervals = args[:intervals]
      if intervals.empty?
        nil
      else
        endpoints = intervals.flat_map { |i| [i['start'], i['end']] }.sort
        center = endpoints[endpoints.length / 2]

        node = call(:create_node, { center: center })
        left_intervals = []
        right_intervals = []

        intervals.each do |interval|
          if interval['end'] < center
            left_intervals << interval
          elsif interval['start'] > center
            right_intervals << interval
          else
            node['intervals'] << interval
          end
        end

        node['intervals'] = node['intervals'].sort_by { |i| [i['start'], i['end']] }
        node['left'] = call(:build_interval_tree, { intervals: left_intervals })
        node['right'] = call(:build_interval_tree, { intervals: right_intervals })

        call(:update_height, { node: node })
        call(:balance_node, { node: node })
      end
    },
    
    # Entry point for finding overlapping intervals
    find_overlapping: ->(connection, root, interval) {
      call(:find_overlapping_with_results, connection, root, interval, [])
    },

    # Recursive helper for finding overlapping intervals
    find_overlapping_with_results: ->(connection, root, interval, results) {
      # Efficiently searches only relevant portions of the tree
      if root
        if interval['end'] < root['center']
          # Query interval is completely to the left
          root['intervals'].each do |stored|
            if stored['start'] <= interval['end']
              results << stored
            end
          end
          call(:find_overlapping_with_results, connection, root['left'], interval, results)
          
        elsif interval['start'] > root['center']
          # Query interval is completely to the right
          root['intervals'].reverse_each do |stored|
            if stored['end'] >= interval['start']
              results << stored
            end
          end
          call(:find_overlapping_with_results, connection, root['right'], interval, results)
          
        else
          # Query interval crosses the center
          results.concat(root['intervals'].select { |i| i['start'] <= interval['end'] && i['end'] >= interval['start'] })
          call(:find_overlapping_with_results, connection, root['left'], interval, results)
          call(:find_overlapping_with_results, connection, root['right'], interval, results)
        end
      end
      results
    },

    # Parses time string and converts to UTC
    parse_time_with_tz: ->(args) {
      time_str = args[:time_str]
      timezone = args[:timezone]

      unless time_str.match?(/^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(?:Z|[+-]\d{2}:?\d{2})?$/)
        call(:error_handler, { message: "Invalid time format: #{time_str}. Expected ISO-8601 format.", details: { time_str: time_str } })
      end

      time = Time.parse(time_str).utc
      call(:logger, { level: 'info', message: 'Parsed time string successfully.', context: { time_str: time_str, timezone: timezone, parsed_time: time } })
      time
    },

    # Processes a single workday schedule
    process_workday: ->(args) {
      workday_data = args[:workday_data]

      timezone = workday_data['interviewer_tmz']
      if timezone.nil? || timezone.empty?
        call(:logger, { level: 'error', message: 'Missing timezone in workday data.', context: workday_data })
        call(:error_handler, { message: 'Timezone is required for scheduling.', details: workday_data })
      end

      start_time = if workday_data['workday_start'].to_s.strip.empty?
        Time.parse("09:00").in_time_zone(timezone)
      else
        call(:parse_time_with_tz, { time_str: workday_data['workday_start'], timezone: timezone })
      end

      end_time = if workday_data['workday_end'].to_s.strip.empty?
        Time.parse("16:00").in_time_zone(timezone)
      else
        call(:parse_time_with_tz, { time_str: workday_data['workday_end'], timezone: timezone })
      end

      if end_time <= start_time
        call(:logger, { level: 'error', message: 'End time is before or equal to start time.', context: { start_time: start_time, end_time: end_time } })
        call(:error_handler, { message: 'End time must be after start time.', details: { start_time: start_time, end_time: end_time } })
      end

      call(:logger, { level: 'info', message: 'Processed workday schedule successfully.', context: { start_time: start_time, end_time: end_time } })
      { 'start' => start_time, 'end' => end_time }
    },

    # Finds the overlapping time window between all workdays
    find_overlap: ->(args) {
      workdays = args[:workdays]

      intersection = workdays.reduce do |result, workday|
        {
          'start' => [result['start'], workday['start']].max,
          'end' => [result['end'], workday['end']].min
        }
      end

      if intersection['start'] >= intersection['end']
        call(:logger, { level: 'error', message: 'No overlap found in workday schedules.', context: workdays })
        call(:error_handler, { message: 'No overlapping time found between schedules.', details: workdays })
      end

      call(:logger, { level: 'info', message: 'Found overlapping schedule successfully.', context: intersection })
      intersection
    },

    # Entry point for finding free time slots
    find_free_slots: ->(args) {
      workday_intersection = args[:workday_intersection]
      tree = args[:tree]

      call(:logger, { level: 'info', message: 'Finding free slots.', context: { workday_intersection: workday_intersection } })
      free_slots = call(:find_free_slots_with_results, { workday_intersection: workday_intersection, tree: tree, free_slots: [], current_time: workday_intersection['start'] })
      call(:logger, { level: 'info', message: 'Found free slots successfully.', context: free_slots })
      free_slots
    },

    # Recursively finds all free time slots
    find_free_slots_with_results: ->(connection, workday_intersection, tree, free_slots, current_time) {
      # Uses interval tree to efficiently skip over busy periods
      if current_time >= workday_intersection['end']
        free_slots
      else
        # Check if current time is in any busy slot
        query = { 'start' => current_time, 'end' => current_time }
        overlapping = call(:find_overlapping, connection, tree, query)
        
        if overlapping.empty?
          # Current time is free, find next busy period
          next_query = {
            'start' => current_time,
            'end' => workday_intersection['end']
          }
          future_overlaps = call(:find_overlapping, connection, tree, next_query)
          slot_end = if future_overlaps.empty?
            workday_intersection['end']
          else
            [future_overlaps.map { |slot| slot['start'] }.min, workday_intersection['end']].min
          end
          
          # Add free slot and continue search
          free_slots << {
            'start' => current_time.iso8601,
            'end' => slot_end.iso8601
          }
          
          call(:find_free_slots_with_results, connection, workday_intersection, tree, free_slots, slot_end)
        else
          # Skip busy period
          next_time = overlapping.map { |slot| slot['end'] }.max
          call(:find_free_slots_with_results, connection, workday_intersection, tree, free_slots, next_time)
        end
      end
    },
    
    # Validates a single schedule input
    validate_schedule: ->(args) {
      schedule = args[:schedule]
      
      # Check for required fields
      %w(workday_start workday_end interviewer_tmz).each do |field|
        if schedule[field].nil? || schedule[field].to_s.strip.empty?
          call(:error_handler, { message: "Missing required field: #{field}", details: schedule })
        end
      end

      # Validate time format (optional fields) - Using regular expression instead of Time.parse
      unless schedule['workday_start'].to_s.strip.empty?
        if !schedule['workday_start'].match?(/^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(?:Z|[+-]\d{2}:?\d{2})?$/)
          call(:error_handler, { message: "Invalid time format for workday_start: #{schedule['workday_start']}", details: schedule })
        end
      end

      unless schedule['workday_end'].to_s.strip.empty?
        if !schedule['workday_end'].match?(/^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(?:Z|[+-]\d{2}:?\d{2})?$/)
          call(:error_handler, { message: "Invalid time format for workday_end: #{schedule['workday_end']}", details: schedule })
        end
      end
    },

    validate_busy_slots: ->(args) {
      busy_slots = args[:busy_slots]
      busy_slots.each do |slot|
        unless slot.key?('calendars')
          call(:error_handler, { message: "Missing 'calendars' key in busy_slots.", details: slot })
        end
        slot['calendars'].each do |_, calendar|
          next unless calendar.key?('busy')
          calendar['busy'].each do |interval|
            %w(start end).each do |field|
              unless interval[field].match?(/^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(?:Z|[+-]\d{2}:?\d{2})?$/)
                call(:error_handler, { message: "Invalid time format for #{field}: #{interval[field]}", details: interval })
              end
            end
          end
        end
      end
    }
  },

  actions: {
    
    # Main action for finding collective available time
    find_collective_availability: {
      title: 'Find Collective Available Time',
      subtitle: 'Calculate overlapping free time slots for all schedules',
      description: 'Finds time slots where all schedules overlap and are free',
      
      # Define input structure for the action
      input_fields: -> {
        [
          {
            name: 'duration',
            label: 'Meeting Duration',
            type: 'integer',
            control_type: 'select',
            pick_list: 'duration_list',
            optional: true,
            hint: 'Duration in minutes'
          },
          {
            name: 'page_size',
            type: 'integer',
            optional: true,
            default: 100,
            hint: 'Number of slots to return'
          },
          {
            name: 'schedules',
            label: 'Schedules',
            type: 'array',
            of: 'object',
            hint: 'Add the working hours for each schedule',
            sticky: true,
            properties: [
              { 
                name: 'workday_start',
                label: 'Workday Start',
                type: 'string',
                control_type: 'date_time',
                hint: 'Select the start time of the workday (empty input causes field to default to 09:00)',
                sticky: true,
                optional: true
              },
              { 
                name: 'workday_end',
                label: 'Workday End',
                type: 'string',
                control_type: 'date_time',
                hint: 'Select the start time of the workday (empty input causes field to default to 09:00)',
                sticky: true,
                optional: true
              },
              { 
                name: 'interviewer_tmz',
                label: 'Timezone',
                control_type: 'select',
                pick_list: 'timezone_list',
                toggle_hint: 'Select from list',
                hint: 'Select the timezone for this schedule',
                sticky: true,
                optional: false,
                toggle_field: {
                  name: 'interviewer_tmz',
                  label: 'Timezone',
                  type: 'string',
                  control_type: 'text',
                  toggle_hint: 'Use custom value',
                  hint: 'Enter an IANA timezone identifier (e.g., America/New_York)'
                }
              }
            ]
          },
          {
            name: 'busy_slots',
            label: 'Busy Slots',
            type: 'array',
            of: 'object',
            hint: 'Add any time slots that are unavailable',
            optional: true,
            sticky: true,
            properties: [
              { 
                name: 'start',
                label: 'Start Time',
                type: 'string',
                control_type: 'date_time',
                hint: 'Select when the busy period starts',
                render_input: 'date_time_picker',
                sticky: true
              },
              { 
                name: 'end',
                label: 'End Time',
                type: 'string',
                control_type: 'date_time',
                hint: 'Select when the busy period ends',
                render_input: 'date_time_picker',
                sticky: true
              }
            ]
          }
        ]
      },
      # Main execution logic
      execute: ->(connection, input) {
        # Validate input existence
        if input['schedules'].nil? || input['schedules'].empty?
          call(:error_handler, { message: "At least one schedule is required.", details: input })
        end

        # Validate schedules
        input['schedules'].each do |schedule|
          call(:validate_schedule, { schedule: schedule })
        end

        # Validate and process schedules
        workdays = input['schedules'].map { |schedule| 
          call(:process_workday, connection, schedule)
        }

        # Find overlapping period
        workday_intersection = call(:find_overlap, connection, workdays)

        # Validate busy slots
        unless input['busy_slots'].nil? || input['busy_slots'].empty?
          input['busy_slots'].each do |slot|
            call(:validate_busy_slot, { slot: slot })
          end
        end
        
        # Handle busy slots with validation
        busy_slots = if input['busy_slots'].nil? || input['busy_slots'].empty?
          []
        else
          input['busy_slots'].map do |slot|
            start_time = Time.parse(slot['start'])
            end_time = Time.parse(slot['end'])
            if end_time <= start_time
              call(:error_handler, { message: "Invalid busy slot: end time must be after start time.", details: input })
            end
            {'start' => start_time, 'end' => end_time }
          end
        end
        
        # Only build tree if we have busy slots
        tree = if busy_slots.empty?
          nil
        else
          call(:build_interval_tree, connection, busy_slots)
        end
        
        # Find available slots
        free_slots = call(:find_free_slots, connection, workday_intersection, tree)

        # Format slots for dropdown
        available_slots = free_slots.map do |slot|
          {
            label: "#{slot['start']} - #{slot['end']}",
            value: "#{slot['start']} - #{slot['end']}"
          }
        end
  
      { available_slots: available_slots }
      },
      # Define output structure
      output_fields: -> {
        [
          {
            name: 'available_slots',
            label: 'Available Slots',
            type: 'array',
            of: 'object',
            properties: [
              { name: 'label', label: 'Label', type: 'string' },
              { name: 'value', label: 'Value', type: 'string' }
            ]
          }
        ]
      }
    }
  }
}
  