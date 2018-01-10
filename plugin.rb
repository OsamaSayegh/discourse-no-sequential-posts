# name: discourse-no-sequential-posts
# about: A plugin to prevent users from creating multiple sequential posts
# version: 0.1
# authors: Osama Sayegh
# url: https://github.com/OsamaSayegh/discourse-no-sequential-posts

enabled_site_setting :no_sequential_posts_plugin_enabled

after_initialize do
  module ::NoSequentialPosts
    def self.get_topic_last_post(topic, guardian)
      last_post = topic.ordered_posts.reject { |post| !guardian.can_see?(post) }.last
      last_post
    end
    
    def self.is_exempted?(user)
      exempted_groups = SiteSetting.no_sequential_posts_exempted_groups.split("|")
      user_groups = user.groups.pluck(:name)
      !(user_groups & exempted_groups).empty?
    end
    
    module ModifiedTopicGuardian
      def can_create_sequential_post?(parent)        
        return false if @user.instance_of?(Guardian::AnonymousUser)
        
        # allow non-human users
        return true if @user.id < 1
        
        guardian = Guardian.new(@user)
        last_post = ::NoSequentialPosts::get_topic_last_post(parent, guardian)
        
        # maybe this is not necessary, but let's keep it just in case
        return true if last_post.post_number == 1
        # allow sequential posts in private messages
        return true if parent.archetype == "private_message"
        # last post in topic doesn't belong to the user trying to post
        return true if last_post.user_id != @user.id
        
        return true if ::NoSequentialPosts::is_exempted?(@user)
        
        not_allowed_window = SiteSetting.no_sequential_posts_until_x_seconds_passed
        return false if not_allowed_window == 0
        
        # allow when last post by the user is old enough
        return true if last_post.created_at < not_allowed_window.seconds.ago
        
        false
      end
      
      def can_create_post_on_topic?(topicOrHash)
        return false if @user.instance_of?(Guardian::AnonymousUser)
        parent = topicOrHash.instance_of?(Topic) ? topicOrHash : topicOrHash[:topic]

        return super(parent) unless SiteSetting.no_sequential_posts_plugin_enabled
        
        skip_sequential_check = topicOrHash.instance_of?(Topic) ? false : topicOrHash[:skip]
        return super(parent) if skip_sequential_check
        
        super(parent) && can_create_sequential_post?(parent)
      end
    end
    
    include ::TopicGuardian
    
    ::TopicGuardian.module_eval { include ModifiedTopicGuardian }
    
    class ::Guardian
      include ModifiedTopicGuardian
    end
  end
  
  add_to_serializer(:current_user, :is_exempted) do
    return unless SiteSetting.no_sequential_posts_plugin_enabled
    ::NoSequentialPosts::is_exempted?(object)
  end

  add_to_serializer(:topic_view, :last_post) do
    return unless SiteSetting.no_sequential_posts_plugin_enabled
    last_post = ::NoSequentialPosts::get_topic_last_post(@object.topic, scope)
    data = {
      user_id: last_post.user_id,
      created_at: last_post.created_at,
      id: last_post.id,
      type: last_post.post_type,
      number: last_post.post_number
    }
    data
  end

  require_dependency 'topic_view_serializer'
  class ::TopicViewSerializer
    old_details = instance_method(:details)
    define_method(:details) do
      result = old_details.bind(self).()
      return result unless SiteSetting.no_sequential_posts_plugin_enabled
      result[:can_create_sequential_post] = scope.can_create_sequential_post?(object.topic)
      result[:can_create_post] = scope.can_create_post_on_topic?(topic: object.topic, skip: true)
      result
    end
  end
end
