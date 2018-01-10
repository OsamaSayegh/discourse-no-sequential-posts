require "rails_helper"

describe TopicsController do
  let(:topic) { Fabricate(:topic, first_post: Fabricate(:post)) }
  let!(:user) { log_in }

  before do
    SiteSetting.no_sequential_posts_plugin_enabled = true
  end

  describe "`last_post` object" do
    let(:normal_post) { Fabricate(:post, topic_id: topic.id) }
    let(:deleted_post) { Fabricate(:post, topic_id: topic.id, deleted_at: Time.now, deleted_by: Fabricate(:admin)) }
    let(:staff_whisper) { Fabricate(:post, topic_id: topic.id, post_type: Post.types[:whisper]) }

    it "should contain data about the last post the user can see" do
      post = normal_post
      whisper = staff_whisper

      get :show, params: { topic_id: topic.id }, format: :json
      expect(response).to be_success

      json = JSON.parse(response.body)
      expect(json["last_post"]).to be_present

      expect(json["last_post"]["user_id"]).to be_present
      expect(json["last_post"]["created_at"]).to be_present
      expect(json["last_post"]["number"]).to be_present
      expect(json["last_post"]["type"]).to be_present

      expect(json["last_post"]["id"]).to eq(post.id)
      expect(json["last_post"]["type"]).to_not eq(Post.types[:whisper])
    end

    it "is never a deleted post" do
      post = normal_post
      deleted = deleted_post
      
      log_in(:admin)

      get :show, params: { topic_id: topic.id }, format: :json
      expect(response).to be_success

      json = JSON.parse(response.body)
      expect(json["last_post"]).to be_present
      expect(json["last_post"]["id"]).to_not eq(deleted.id)      
      expect(json["last_post"]["id"]).to eq(post.id)      
    end
  end

  describe "`details` object" do
    it "has a `can_create_sequential_post` attribute" do
      get :show, params: { topic_id: topic.id }, format: :json
      expect(response).to be_success

      json = JSON.parse(response.body)
      expect(json["details"]["can_create_sequential_post"]).to be_present
    end
  end
end
