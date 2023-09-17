module Agents
  class YoutubeAgent < Agent
    include FormConfigurable
    can_dry_run!
    no_bulk_receive!
    default_schedule 'every_1h'

    description do
      <<-MD
      The Youtube Agent interacts with Youtube API.

      `debug` is used for verbose mode.

      `youtube_api_key` is needed for authentication.

      `channel_id` is the id of the channel.

      `playlist_id` is the id of the playlist.

      `limit` is the max number of results.

      `type` is for the wanted action like check_videos.

      `expected_receive_period_in_days` is used to determine if the Agent is working. Set it to the maximum number of days
      that you anticipate passing without this Agent receiving an incoming Event.
      MD
    end

    event_description <<-MD
      Events look like this:

          {
            "kind": "youtube#searchResult",
            "etag": "Q0TmoqzRcRGCScTDXGKO1XkTQAQ",
            "id": {
              "kind": "youtube#video",
              "videoId": "h46EvTIB1D0"
            },
            "snippet": {
              "publishedAt": "2023-07-24T16:40:18Z",
              "channelId": "UC1WMae32v_eJ8qOtLQqM26Q",
              "title": "Edge Computing &amp; 5G to Supercharge Blockchains",
              "description": "Multilingual Subtitles Available! In this episode of CallistoTalks, we explore the future of blockchain systems, supercharged by ...",
              "thumbnails": {
                "default": {
                  "url": "https://i.ytimg.com/vi/h46EvTIB1D0/default.jpg",
                  "width": 120,
                  "height": 90
                },
                "medium": {
                  "url": "https://i.ytimg.com/vi/h46EvTIB1D0/mqdefault.jpg",
                  "width": 320,
                  "height": 180
                },
                "high": {
                  "url": "https://i.ytimg.com/vi/h46EvTIB1D0/hqdefault.jpg",
                  "width": 480,
                  "height": 360
                }
              },
              "channelTitle": "Callisto Network",
              "liveBroadcastContent": "none",
              "publishTime": "2023-07-24T16:40:18Z"
            }
          }
    MD

    def default_options
      {
        'channel_id' => '',
        'playlist_id' => '',
        'youtube_api_key' => '',
        'limit' => '10',
        'type' => 'check_channel',
        'debug' => 'false',
        'expected_receive_period_in_days' => '2',
      }
    end

    form_configurable :youtube_api_key, type: :string
    form_configurable :channel_id, type: :string
    form_configurable :playlist_id, type: :string
    form_configurable :limit, type: :number
    form_configurable :debug, type: :boolean
    form_configurable :expected_receive_period_in_days, type: :string
    form_configurable :type, type: :array, values: ['check_channel', 'check_playlist', 'check_videos']
    def validate_options
      errors.add(:base, "type has invalid value: should be 'check_channel', 'check_playlist', 'check_videos'") if interpolated['type'].present? && !%w(check_channel check_playlist check_videos).include?(interpolated['type'])

      unless options['playlist_id'].present? || !['check_playlist'].include?(options['type'])
        errors.add(:base, "playlist_id is a required field")
      end

      unless options['channel_id'].present? || !['check_channel' 'check_videos'].include?(options['type'])
        errors.add(:base, "channel_id is a required field")
      end

      unless options['youtube_api_key'].present? || !['check_channel' 'check_playlist' 'check_videos'].include?(options['type'])
        errors.add(:base, "youtube_api_key is a required field")
      end

      unless options['limit'].present? || !['check_playlist'].include?(options['type'])
        errors.add(:base, "limit is a required field")
      end

      if options.has_key?('debug') && boolify(options['debug']).nil?
        errors.add(:base, "if provided, debug must be true or false")
      end

      unless options['expected_receive_period_in_days'].present? && options['expected_receive_period_in_days'].to_i > 0
        errors.add(:base, "Please provide 'expected_receive_period_in_days' to indicate how many days can pass before this Agent is considered to be not working")
      end
    end

    def working?
      event_created_within?(options['expected_receive_period_in_days']) && !recent_error_logs?
    end

    def receive(incoming_events)
      incoming_events.each do |event|
        interpolate_with(event) do
          log event
          trigger_action
        end
      end
    end

    def check
      trigger_action
    end

    private

    def log_curl_output(code,body)

      log "request status : #{code}"

      if interpolated['debug'] == 'true'
        log "body"
        log body
      end

    end

    def check_channel()

      uri = URI.parse("https://youtube.googleapis.com/youtube/v3/channels?part=snippet%2CcontentDetails%2Cstatistics&id=#{interpolated['channel_id']}&key=#{interpolated['youtube_api_key']}")
      request = Net::HTTP::Get.new(uri)
      request["Accept"] = "application/json"

      req_options = {
        use_ssl: uri.scheme == "https",
      }

      response = Net::HTTP.start(uri.hostname, uri.port, req_options) do |http|
        http.request(request)
      end

      log_curl_output(response.code,response.body)

      payload = JSON.parse(response.body)
      if !memory['last_status'] || (memory['last_status'].present? && payload != memory['last_status'])
        create_event payload: payload
        memory['last_status'] = payload
      else
        if interpolated['debug'] == 'true'
          log "nothing to compare"
        end
      end

    end

    def check_playlist()

      uri = URI.parse("https://www.googleapis.com/youtube/v3/playlistItems?key=#{interpolated['youtube_api_key']}&playlistId=#{interpolated['playlist_id']}&part=snippet,contentDetails,status&maxResults=#{interpolated['limit']}")
      request = Net::HTTP::Get.new(uri)
      request["Accept"] = "application/json"

      req_options = {
        use_ssl: uri.scheme == "https",
      }

      response = Net::HTTP.start(uri.hostname, uri.port, req_options) do |http|
        http.request(request)
      end

      log_curl_output(response.code,response.body)

      payload = JSON.parse(response.body)
      if !memory['last_status']
        payload['items'].each do |playlist|
          create_event payload: playlist
        end
        memory['last_status'] = payload
      else
        if payload != memory['last_status']
          if memory['last_status'] == ''
          else
            last_status = memory['last_status']
            payload['items'].each do |playlist|
              found = false
              if interpolated['debug'] == 'true'
                log "playlist"
                log playlist
              end
              last_status['items'].each do |playlistbis|
                if playlist == playlistbis
                  found = true
                end
                if interpolated['debug'] == 'true'
                  log "playlistbis"
                  log playlistbis
                  log "found is #{found}!"
                end
              end
              if found == false
                create_event payload: playlist
              end
            end
          end
          memory['last_status'] = payload
        else
          if interpolated['debug'] == 'true'
            log "nothing to compare"
          end
        end
      end

    end

    def check_videos()

      uri = URI.parse("https://www.googleapis.com/youtube/v3/search?key=#{interpolated['youtube_api_key']}&channelId=#{interpolated['channel_id']}&part=snippet,id&order=date&maxResults=#{interpolated['limit']}")
      request = Net::HTTP::Get.new(uri)
      request["Accept"] = "application/json"

      req_options = {
        use_ssl: uri.scheme == "https",
      }

      response = Net::HTTP.start(uri.hostname, uri.port, req_options) do |http|
        http.request(request)
      end

      log_curl_output(response.code,response.body)

      payload = JSON.parse(response.body)
      if !memory['last_status']
        payload['items'].each do |video|
          create_event payload: video
        end
        memory['last_status'] = payload
      else
        if payload != memory['last_status']
          if memory['last_status'] == ''
          else
            last_status = memory['last_status']
            payload['items'].each do |video|
              found = false
              if interpolated['debug'] == 'true'
                log "video"
                log video
              end
              last_status['items'].each do |videobis|
                if video['id'] == videobis['id']
                  found = true
                end
                if interpolated['debug'] == 'true'
                  log "videobis"
                  log videobis
                  log "found is #{found}!"
                end
              end
              if found == false
                create_event payload: video
              end
            end
          end
          memory['last_status'] = payload
        else
          if interpolated['debug'] == 'true'
            log "nothing to compare"
          end
        end
      end
    end

    def trigger_action

      case interpolated['type']
      when "check_channel"
        check_channel()
      when "check_playlist"
        check_playlist()
      when "check_videos"
        check_videos()
      else
        log "Error: type has an invalid value (#{interpolated['type']})"
      end
    end
  end
end
