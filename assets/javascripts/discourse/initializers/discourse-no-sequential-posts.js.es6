import { withPluginApi } from 'discourse/lib/plugin-api';
import { observes } from 'ember-addons/ember-computed-decorators';

function leadingZeros(num, size) {
  num = num.toString();
  while (num.length < size) {
    num = '0' + num;
  }
  return num;
}

function msToTimer (ms) {
  let remaining = ms / 1000;
  const hours = Math.floor(remaining / 3600);
  remaining = remaining - hours * 3600;
  const mins = Math.floor(remaining / 60);
  remaining = remaining - mins * 60;
  const secs = Math.floor(remaining);
  return {
    hours: leadingZeros(hours, 2),
    mins: leadingZeros(mins, 2),
    secs: leadingZeros(secs, 2)
  };
}

function initializeWithApi(api) {
  if (Discourse.SiteSettings.no_sequential_posts_plugin_enabled) {
    api.modifyClass('controller:topic', {
      // nsp is the first letters of "No Sequential Posts"
      // prefix everything thing we add to the controller with 'nsp_' so that
      // it reduces the odds of colliding with Discourse's native stuff in the future
      nsp_canReplySequential: Ember.computed.alias('model.details.can_create_sequential_post'),
      nsp_lastPost: Ember.computed.alias('model.last_post'),
      nsp_timeLeft: 0,

      @observes('model.postStream.posts.length')
      nsp_setLastPost() {
        const lastPost = _.last(this.get('model.postStream.posts'));
        if (lastPost && lastPost.get('post_number') === this.get('model.highest_post_number')) {
          this.set('nsp_lastPost', {
            created_at: lastPost.get('created_at'),
            user_id: lastPost.get('user_id'),
            id: lastPost.get('id'),
            type: lastPost.get('post_type'),
            number: lastPost.get('post_number')
          });
        }
      },

      @observes('nsp_lastPost.id', 'nsp_timeLeft')
      nsp_lastPostUpdated() {
        if (this.nsp_shouldApplyRestriction()) {
          this.nsp_applyRestriction();
        } else {
          this.nsp_removeRestriction();
        }
      },

      nsp_calculateTimeLeft() {
        const notAllowedWindow = this.siteSettings.no_sequential_posts_until_x_seconds_passed * 1000;
        const lastPostCreatedAt = new Date(this.get('nsp_lastPost.created_at')).getTime();
        return lastPostCreatedAt - (Date.now() - notAllowedWindow);
      },

      nsp_timerModalContent() {
        const canPost = !this.nsp_shouldApplyRestriction();
        if (canPost) {
          return I18n.t("no_sequential_posts.can_post");
        }
        const indefiniteWait = this.siteSettings.no_sequential_posts_until_x_seconds_passed === 0;
        if (indefiniteWait) {
          return I18n.t("no_sequential_posts.cant_post");
        }
        const timer = msToTimer(this.nsp_calculateTimeLeft());
        return I18n.t("no_sequential_posts.cant_post_and_time", timer);
      },

      nsp_updateTimerModal() {
        const $timerModal = this.get('nsp_timerModal');
        if ($timerModal) {
          $timerModal.text(this.nsp_timerModalContent());
        }
      },

      nsp_updateTimeLeft() {
        let timeLeft = this.nsp_calculateTimeLeft();
        timeLeft = timeLeft > 0 ? timeLeft : 0;
        this.set('nsp_timeLeft', timeLeft);
        this.nsp_updateTimerModal();
      },

      nsp_applyRestriction() {
        if (!this.get('nsp_restrictionApplied')) {
          this.set('nsp_canReplySequential', false);
          this.set('nsp_intervalId', window.setInterval(() => this.nsp_updateTimeLeft(), 1000));
          this.set('nsp_restrictionApplied', true);
        }
      },

      nsp_removeRestriction () {
        if (this.get('nsp_restrictionApplied')) {
          this.set('nsp_canReplySequential', true);
          window.clearInterval(this.get('nsp_intervalId'))
          this.set('nsp_intervalId', null);
          this.set('nsp_timeLeft', 0);
          this.set('nsp_restrictionApplied', false);
          this.nsp_updateTimerModal();
        }
      },

      nsp_shouldApplyRestriction() {
        const lastPost = this.get('nsp_lastPost');
        if (!lastPost) { return; }

        if (lastPost.number === 1) {
          return false;
        }

        if (lastPost.user_id !== this.get('currentUser.id')) {
          return false;
        }
        if (this.get('model.archetype') === 'private_message') {
          return false;
        }

        if (this.get('currentUser.is_exempted')) {
          return false;
        }

        const notAllowedWindow = this.siteSettings.no_sequential_posts_until_x_seconds_passed;
        if (notAllowedWindow === 0) {
          return true;
        }
        if (this.nsp_calculateTimeLeft() <= 0) {
          return false;
        }

        return true;
      },

      actions: {
        replyToPost(post) {
          if (this.get('model.details.can_create_post') && this.nsp_shouldApplyRestriction()) {
            bootbox.alert(this.nsp_timerModalContent());
            this.set('nsp_timerModal', $('.bootbox.modal.in .modal-body'));
          } else {
            this._super(...arguments);
          }
        }
      }
    })
  }
}

export default {
  name: 'discourse-no-sequential-posts',
  initialize() {
    withPluginApi('0.8.13', initializeWithApi);
  }
};
