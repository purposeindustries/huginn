require 'rubypress'

module Agents
  class WordpressAgent < Agent
    cannot_be_scheduled!

    gem_dependency_check { defined?(Rubypress) }

    description <<-MD
      #{'## Include `rubypress` in your Gemfile to use this Agent!' if dependencies_missing?}
      `username`: username to log in (required)

      `password`: password (required)

      `host`: host of the server (required)

      `port`: port of the server (optional)

      `post_status`: status of the post (`publish` or `draft`, [docs](https://codex.wordpress.org/Post_Status)) (default to publish, optional)

      `title`: title of the post (required)

      `content`: content of the post (required)

      `name`: the url to be used (slug) (optional)

      `post_author`: author of the post, 1 for admin (default to 1, optional)

      `categories`: comma separated list of categories which should be added to the post (optional)

      `tags`: comma separated list of tags which should be added to the post (optional)

      `blog_id`: id the of blog if you're using multisite wp, otherwise 1 (default to 1, optional)

      `use_ssl`: whether to use ssl (wordpress.com requires this) (default to false, optional)

      `ssl_port`: if `use_ssl` is set to true, what ssl port to use (default to 443, optional)
    MD

    def validate_options
      errors.add(:base, "expected_update_period_in_days is required") unless options['expected_update_period_in_days'].present?
    end

    def working?
      event_created_within?(options['expected_update_period_in_days']) && most_recent_event && most_recent_event.payload['success'] == true && !recent_error_logs?
    end

    def default_options
      {
        'expected_update_period_in_days' => "10",
        'message' => "{{text}}",
        'path' => '/xmlrpc.php',
        'blog_id' => '0',
        'post_status' => 'publish',
        'post_author' => '1',
        'port' => 80,
        'use_ssl' => false,
        'ssl_port' => 443
      }
    end

    def receive(incoming_events)
      incoming_events.each do |event|
        payload = interpolated(event)
        #return puts "payload: #{payload.inspect}"
        client_opts = {
          :host => payload['host'],
          :port => payload['port'].to_i,
          :username => payload['username'],
          :password => payload['password'],
          :path => payload['path'],
          :use_ssl => boolify(payload['use_ssl']),
          :ssl_port => payload['ssl_port'].to_i,
          :debug => true
        }
        status = payload['post_status']
        content = payload['content']
        title = payload['title']
        name = payload['name'].to_s
        author = payload['post_author']
        categories = payload['categories'].to_s.split(',')
        tags = payload['tags'].to_s.split(',')
        blog_id = payload['blog_id'] #.to_i
        custom_fields = payload['custom_fields']
        post_opts = {
          :blog_id => blog_id,
          :content => {
            :post_status  => status,
            :post_date    => Time.now.utc,
            :post_content => content,
            :post_title   => title,
            :post_name    => name,
            :post_author  => author, # 1 if there is only the admin user, otherwise the user's id
            :terms_names  => {
              :category   => categories,
              :post_tag => tags
            },
            :custom_fields => custom_fields
          }
        }
        id = create_post(client_opts, post_opts)
        post = get_post(client_opts, id)
        create_event :payload => {
          'success' => true,
          'post_id' => id,
          'agent_id' => event.agent_id,
          'event_id' => event.id,
          'post' => post.to_hash
        }
      end #end of do
    end # end of receive
    def create_post(client_opts, post_opts)
      client = Rubypress::Client.new(client_opts)
      puts "opts:"
      puts post_opts.to_json
      client.newPost(post_opts);
    end # end of create_post

    def get_post(client_opts, id)
      client = Rubypress::Client.new(client_opts)
      puts "getting #{id}"
      client.getPost({
        :post_id => id
      })
    end # end of get_post
  end # end of class
end # end of module
