require 'spec_helper'

describe Repository, models: true do
  include RepoHelpers
  TestBlob = Struct.new(:name)

  let(:project) { create(:project) }
  let(:repository) { project.repository }
  let(:user) { create(:user) }
  let(:commit_options) do
    author = repository.user_to_committer(user)
    { message: 'Test message', committer: author, author: author }
  end
  let(:merge_commit) do
    merge_request = create(:merge_request, source_branch: 'feature', target_branch: 'master', source_project: project)
    merge_commit_id = repository.merge(user, merge_request, commit_options)
    repository.commit(merge_commit_id)
  end

  describe '#branch_names_contains' do
    subject { repository.branch_names_contains(sample_commit.id) }

    it { is_expected.to include('master') }
    it { is_expected.not_to include('feature') }
    it { is_expected.not_to include('fix') }
  end

  describe '#tag_names_contains' do
    subject { repository.tag_names_contains(sample_commit.id) }

    it { is_expected.to include('v1.1.0') }
    it { is_expected.not_to include('v1.0.0') }
  end

  describe 'tags_sorted_by' do
    context 'name' do
      subject { repository.tags_sorted_by('name').map(&:name) }

      it { is_expected.to eq(['v1.1.0', 'v1.0.0']) }
    end

    context 'updated' do
      let(:tag_a) { repository.find_tag('v1.0.0') }
      let(:tag_b) { repository.find_tag('v1.1.0') }

      context 'desc' do
        subject { repository.tags_sorted_by('updated_desc').map(&:name) }

        before do
          double_first = double(committed_date: Time.now)
          double_last = double(committed_date: Time.now - 1.second)

          allow(tag_a).to receive(:target).and_return(double_first)
          allow(tag_b).to receive(:target).and_return(double_last)
          allow(repository).to receive(:tags).and_return([tag_a, tag_b])
        end

        it { is_expected.to eq(['v1.0.0', 'v1.1.0']) }
      end

      context 'asc' do
        subject { repository.tags_sorted_by('updated_asc').map(&:name) }

        before do
          double_first = double(committed_date: Time.now - 1.second)
          double_last = double(committed_date: Time.now)

          allow(tag_a).to receive(:target).and_return(double_last)
          allow(tag_b).to receive(:target).and_return(double_first)
          allow(repository).to receive(:tags).and_return([tag_a, tag_b])
        end

        it { is_expected.to eq(['v1.1.0', 'v1.0.0']) }
      end
    end
  end

  describe '#last_commit_for_path' do
    subject { repository.last_commit_for_path(sample_commit.id, '.gitignore').id }

    it { is_expected.to eq('c1acaa58bbcbc3eafe538cb8274ba387047b69f8') }
  end

  describe '#find_commits_by_message' do
    subject { repository.find_commits_by_message('submodule').map{ |k| k.id } }

    it { is_expected.to include('5937ac0a7beb003549fc5fd26fc247adbce4a52e') }
    it { is_expected.to include('6f6d7e7ed97bb5f0054f2b1df789b39ca89b6ff9') }
    it { is_expected.to include('cfe32cf61b73a0d5e9f13e774abde7ff789b1660') }
    it { is_expected.not_to include('913c66a37b4a45b9769037c55c2d238bd0942d2e') }
  end

  describe '#blob_at' do
    context 'blank sha' do
      subject { repository.blob_at(Gitlab::Git::BLANK_SHA, '.gitignore') }

      it { is_expected.to be_nil }
    end
  end

  describe '#merged_to_root_ref?' do
    context 'merged branch' do
      subject { repository.merged_to_root_ref?('improve/awesome') }

      it { is_expected.to be_truthy }
    end
  end

  describe '#can_be_merged?' do
    context 'mergeable branches' do
      subject { repository.can_be_merged?('0b4bc9a49b562e85de7cc9e834518ea6828729b9', 'master') }

      it { is_expected.to be_truthy }
    end

    context 'non-mergeable branches' do
      subject { repository.can_be_merged?('bb5206fee213d983da88c47f9cf4cc6caf9c66dc', 'feature') }

      it { is_expected.to be_falsey }
    end

    context 'non merged branch' do
      subject { repository.merged_to_root_ref?('fix') }

      it { is_expected.to be_falsey }
    end

    context 'non existent branch' do
      subject { repository.merged_to_root_ref?('non_existent_branch') }

      it { is_expected.to be_nil }
    end
  end

  describe :commit_file do
    it 'commits change to a file successfully' do
      expect do
        repository.commit_file(user, 'CHANGELOG', 'Changelog!',
                              'Updates file content',
                              'master', true)
      end.to change { repository.commits('master').count }.by(1)

      blob = repository.blob_at('master', 'CHANGELOG')

      expect(blob.data).to eq('Changelog!')
    end
  end

  describe :update_file do
    it 'updates filename successfully' do
      expect do
        repository.update_file(user, 'NEWLICENSE', 'Copyright!',
                                     branch: 'master',
                                     previous_path: 'LICENSE',
                                     message: 'Changes filename')
      end.to change { repository.commits('master').count }.by(1)

      files = repository.ls_files('master')

      expect(files).not_to include('LICENSE')
      expect(files).to include('NEWLICENSE')
    end
  end

  describe "search_files" do
    let(:results) { repository.search_files('feature', 'master') }
    subject { results }

    it { is_expected.to be_an Array }

    it 'regex-escapes the query string' do
      results = repository.search_files("test\\", 'master')

      expect(results.first).not_to start_with('fatal:')
    end

    it 'properly handles an unmatched parenthesis' do
      results = repository.search_files("test(", 'master')

      expect(results.first).not_to start_with('fatal:')
    end

    describe 'result' do
      subject { results.first }

      it { is_expected.to be_an String }
      it { expect(subject.lines[2]).to eq("master:CHANGELOG:188:  - Feature: Replace teams with group membership\n") }
    end

    describe 'parsing result' do
      subject { repository.parse_search_result(search_result) }
      let(:search_result) { results.first }

      it { is_expected.to be_an OpenStruct }
      it { expect(subject.filename).to eq('CHANGELOG') }
      it { expect(subject.basename).to eq('CHANGELOG') }
      it { expect(subject.ref).to eq('master') }
      it { expect(subject.startline).to eq(186) }
      it { expect(subject.data.lines[2]).to eq("  - Feature: Replace teams with group membership\n") }

      context "when filename has extension" do
        let(:search_result) { "master:CONTRIBUTE.md:5:- [Contribute to GitLab](#contribute-to-gitlab)\n" }

        it { expect(subject.filename).to eq('CONTRIBUTE.md') }
        it { expect(subject.basename).to eq('CONTRIBUTE') }
      end

      context "when file under directory" do
        let(:search_result) { "master:a/b/c.md:5:a b c\n" }

        it { expect(subject.filename).to eq('a/b/c.md') }
        it { expect(subject.basename).to eq('a/b/c') }
      end
    end
  end

  describe "#changelog" do
    before do
      repository.send(:cache).expire(:changelog)
    end

    it 'accepts changelog' do
      expect(repository.tree).to receive(:blobs).and_return([TestBlob.new('changelog')])

      expect(repository.changelog.name).to eq('changelog')
    end

    it 'accepts news instead of changelog' do
      expect(repository.tree).to receive(:blobs).and_return([TestBlob.new('news')])

      expect(repository.changelog.name).to eq('news')
    end

    it 'accepts history instead of changelog' do
      expect(repository.tree).to receive(:blobs).and_return([TestBlob.new('history')])

      expect(repository.changelog.name).to eq('history')
    end

    it 'accepts changes instead of changelog' do
      expect(repository.tree).to receive(:blobs).and_return([TestBlob.new('changes')])

      expect(repository.changelog.name).to eq('changes')
    end

    it 'is case-insensitive' do
      expect(repository.tree).to receive(:blobs).and_return([TestBlob.new('CHANGELOG')])

      expect(repository.changelog.name).to eq('CHANGELOG')
    end
  end

  describe "#license_blob" do
    before do
      repository.send(:cache).expire(:license_blob)
      repository.remove_file(user, 'LICENSE', 'Remove LICENSE', 'master')
    end

    it 'handles when HEAD points to non-existent ref' do
      repository.commit_file(user, 'LICENSE', 'Copyright!', 'Add LICENSE', 'master', false)
      rugged = double('rugged')
      expect(rugged).to receive(:head_unborn?).and_return(true)
      expect(repository).to receive(:rugged).and_return(rugged)

      expect(repository.license_blob).to be_nil
    end

    it 'looks in the root_ref only' do
      repository.remove_file(user, 'LICENSE', 'Remove LICENSE', 'markdown')
      repository.commit_file(user, 'LICENSE', Licensee::License.new('mit').content, 'Add LICENSE', 'markdown', false)

      expect(repository.license_blob).to be_nil
    end

    it 'detects license file with no recognizable open-source license content' do
      repository.commit_file(user, 'LICENSE', 'Copyright!', 'Add LICENSE', 'master', false)

      expect(repository.license_blob.name).to eq('LICENSE')
    end

    %w[LICENSE LICENCE LiCensE LICENSE.md LICENSE.foo COPYING COPYING.md].each do |filename|
      it "detects '#{filename}'" do
        repository.commit_file(user, filename, Licensee::License.new('mit').content, "Add #{filename}", 'master', false)

        expect(repository.license_blob.name).to eq(filename)
      end
    end
  end

  describe '#license_key' do
    before do
      repository.send(:cache).expire(:license_key)
      repository.remove_file(user, 'LICENSE', 'Remove LICENSE', 'master')
    end

    it 'handles when HEAD points to non-existent ref' do
      repository.commit_file(user, 'LICENSE', 'Copyright!', 'Add LICENSE', 'master', false)
      rugged = double('rugged')
      expect(rugged).to receive(:head_unborn?).and_return(true)
      expect(repository).to receive(:rugged).and_return(rugged)

      expect(repository.license_key).to be_nil
    end

    it 'returns nil when no license is detected' do
      expect(repository.license_key).to be_nil
    end

    it 'detects license file with no recognizable open-source license content' do
      repository.commit_file(user, 'LICENSE', 'Copyright!', 'Add LICENSE', 'master', false)

      expect(repository.license_key).to be_nil
    end

    it 'returns the license key' do
      repository.commit_file(user, 'LICENSE', Licensee::License.new('mit').content, 'Add LICENSE', 'master', false)

      expect(repository.license_key).to eq('mit')
    end
  end

  describe "#gitlab_ci_yml" do
    it 'returns valid file' do
      files = [TestBlob.new('file'), TestBlob.new('.gitlab-ci.yml'), TestBlob.new('copying')]
      expect(repository.tree).to receive(:blobs).and_return(files)

      expect(repository.gitlab_ci_yml.name).to eq('.gitlab-ci.yml')
    end

    it 'returns nil if not exists' do
      expect(repository.tree).to receive(:blobs).and_return([])
      expect(repository.gitlab_ci_yml).to be_nil
    end

    it 'returns nil for empty repository' do
      expect(repository).to receive(:empty?).and_return(true)
      expect(repository.gitlab_ci_yml).to be_nil
    end
  end

  describe '#add_branch' do
    context 'when pre hooks were successful' do
      it 'runs without errors' do
        hook = double(trigger: [true, nil])
        expect(Gitlab::Git::Hook).to receive(:new).exactly(3).times.and_return(hook)

        expect { repository.add_branch(user, 'new_feature', 'master') }.not_to raise_error
      end

      it 'creates the branch' do
        allow_any_instance_of(Gitlab::Git::Hook).to receive(:trigger).and_return([true, nil])

        branch = repository.add_branch(user, 'new_feature', 'master')

        expect(branch.name).to eq('new_feature')
      end

      it 'calls the after_create_branch hook' do
        expect(repository).to receive(:after_create_branch)

        repository.add_branch(user, 'new_feature', 'master')
      end
    end

    context 'when pre hooks failed' do
      it 'gets an error' do
        allow_any_instance_of(Gitlab::Git::Hook).to receive(:trigger).and_return([false, ''])

        expect do
          repository.add_branch(user, 'new_feature', 'master')
        end.to raise_error(GitHooksService::PreReceiveError)
      end

      it 'does not create the branch' do
        allow_any_instance_of(Gitlab::Git::Hook).to receive(:trigger).and_return([false, ''])

        expect do
          repository.add_branch(user, 'new_feature', 'master')
        end.to raise_error(GitHooksService::PreReceiveError)
        expect(repository.find_branch('new_feature')).to be_nil
      end
    end
  end

  describe '#find_branch' do
    it 'loads a branch with a fresh repo' do
      expect(Gitlab::Git::Repository).to receive(:new).twice.and_call_original

      2.times do
        expect(repository.find_branch('feature')).not_to be_nil
      end
    end

    it 'loads a branch with a cached repo' do
      expect(Gitlab::Git::Repository).to receive(:new).once.and_call_original

      2.times do
        expect(repository.find_branch('feature', fresh_repo: false)).not_to be_nil
      end
    end
  end

  describe '#rm_branch' do
    let(:old_rev) { '0b4bc9a49b562e85de7cc9e834518ea6828729b9' } # git rev-parse feature
    let(:blank_sha) { '0000000000000000000000000000000000000000' }

    context 'when pre hooks were successful' do
      it 'runs without errors' do
        expect_any_instance_of(GitHooksService).to receive(:execute).
          with(user, project.repository.path_to_repo, old_rev, blank_sha, 'refs/heads/feature')

        expect { repository.rm_branch(user, 'feature') }.not_to raise_error
      end

      it 'deletes the branch' do
        allow_any_instance_of(Gitlab::Git::Hook).to receive(:trigger).and_return([true, nil])

        expect { repository.rm_branch(user, 'feature') }.not_to raise_error

        expect(repository.find_branch('feature')).to be_nil
      end
    end

    context 'when pre hooks failed' do
      it 'gets an error' do
        allow_any_instance_of(Gitlab::Git::Hook).to receive(:trigger).and_return([false, ''])

        expect do
          repository.rm_branch(user, 'new_feature')
        end.to raise_error(GitHooksService::PreReceiveError)
      end

      it 'does not delete the branch' do
        allow_any_instance_of(Gitlab::Git::Hook).to receive(:trigger).and_return([false, ''])

        expect do
          repository.rm_branch(user, 'feature')
        end.to raise_error(GitHooksService::PreReceiveError)
        expect(repository.find_branch('feature')).not_to be_nil
      end
    end
  end

  describe '#update_branch_with_hooks' do
    let(:old_rev) { '0b4bc9a49b562e85de7cc9e834518ea6828729b9' } # git rev-parse feature
    let(:new_rev) { 'a74ae73c1ccde9b974a70e82b901588071dc142a' } # commit whose parent is old_rev

    context 'when pre hooks were successful' do
      before do
        expect_any_instance_of(GitHooksService).to receive(:execute).
          with(user, repository.path_to_repo, old_rev, new_rev, 'refs/heads/feature').
          and_yield.and_return(true)
      end

      it 'runs without errors' do
        expect do
          repository.update_branch_with_hooks(user, 'feature') { new_rev }
        end.not_to raise_error
      end

      it 'ensures the autocrlf Git option is set to :input' do
        expect(repository).to receive(:update_autocrlf_option)

        repository.update_branch_with_hooks(user, 'feature') { new_rev }
      end

      context "when the branch wasn't empty" do
        it 'updates the head' do
          expect(repository.find_branch('feature').target.id).to eq(old_rev)
          repository.update_branch_with_hooks(user, 'feature') { new_rev }
          expect(repository.find_branch('feature').target.id).to eq(new_rev)
        end
      end
    end

    context 'when the update adds more than one commit' do
      it 'runs without errors' do
        old_rev = '33f3729a45c02fc67d00adb1b8bca394b0e761d9'

        # old_rev is an ancestor of new_rev
        expect(repository.rugged.merge_base(old_rev, new_rev)).to eq(old_rev)

        # old_rev is not a direct ancestor (parent) of new_rev
        expect(repository.rugged.lookup(new_rev).parent_ids).not_to include(old_rev)

        branch = 'feature-ff-target'
        repository.add_branch(user, branch, old_rev)

        expect { repository.update_branch_with_hooks(user, branch) { new_rev } }.not_to raise_error
      end
    end

    context 'when the update would remove commits from the target branch' do
      it 'raises an exception' do
        branch = 'master'
        old_rev = repository.find_branch(branch).target.sha

        # The 'master' branch is NOT an ancestor of new_rev.
        expect(repository.rugged.merge_base(old_rev, new_rev)).not_to eq(old_rev)

        # Updating 'master' to new_rev would lose the commits on 'master' that
        # are not contained in new_rev. This should not be allowed.
        expect do
          repository.update_branch_with_hooks(user, branch) { new_rev }
        end.to raise_error(Repository::CommitError)
      end
    end

    context 'when pre hooks failed' do
      it 'gets an error' do
        allow_any_instance_of(Gitlab::Git::Hook).to receive(:trigger).and_return([false, ''])

        expect do
          repository.update_branch_with_hooks(user, 'feature') { new_rev }
        end.to raise_error(GitHooksService::PreReceiveError)
      end
    end

    context 'when target branch is different from source branch' do
      before do
        allow_any_instance_of(Gitlab::Git::Hook).to receive(:trigger).and_return([true, ''])
        allow(repository).to receive(:update_ref!)
      end

      it 'expires branch cache' do
        expect(repository).not_to receive(:expire_exists_cache)
        expect(repository).not_to receive(:expire_root_ref_cache)
        expect(repository).not_to receive(:expire_emptiness_caches)
        expect(repository).to     receive(:expire_branches_cache)
        expect(repository).to     receive(:expire_has_visible_content_cache)
        expect(repository).to     receive(:expire_branch_count_cache)

        repository.update_branch_with_hooks(user, 'new-feature') { new_rev }
      end
    end

    context 'when repository is empty' do
      before do
        allow_any_instance_of(Gitlab::Git::Hook).to receive(:trigger).and_return([true, ''])
      end

      it 'expires creation and branch cache' do
        empty_repository = create(:empty_project, :empty_repo).repository

        expect(empty_repository).to receive(:expire_exists_cache)
        expect(empty_repository).to receive(:expire_root_ref_cache)
        expect(empty_repository).to receive(:expire_emptiness_caches)
        expect(empty_repository).to receive(:expire_branches_cache)
        expect(empty_repository).to receive(:expire_has_visible_content_cache)
        expect(empty_repository).to receive(:expire_branch_count_cache)

        empty_repository.commit_file(user, 'CHANGELOG', 'Changelog!',
                                     'Updates file content', 'master', false)
      end
    end
  end

  describe '#exists?' do
    it 'returns true when a repository exists' do
      expect(repository.exists?).to eq(true)
    end

    it 'returns false when a repository does not exist' do
      expect(repository.raw_repository).to receive(:rugged).
        and_raise(Gitlab::Git::Repository::NoRepository)

      expect(repository.exists?).to eq(false)
    end

    it 'returns false when there is no namespace' do
      allow(repository).to receive(:path_with_namespace).and_return(nil)

      expect(repository.exists?).to eq(false)
    end
  end

  describe '#has_visible_content?' do
    subject { repository.has_visible_content? }

    describe 'when there are no branches' do
      before do
        allow(repository).to receive(:branch_count).and_return(0)
      end

      it { is_expected.to eq(false) }
    end

    describe 'when there are branches' do
      it 'returns true' do
        expect(repository).to receive(:branch_count).and_return(3)

        expect(subject).to eq(true)
      end

      it 'caches the output' do
        expect(repository).to receive(:branch_count).
          once.
          and_return(3)

        repository.has_visible_content?
        repository.has_visible_content?
      end
    end
  end

  describe '#update_autocrlf_option' do
    describe 'when autocrlf is not already set to :input' do
      before do
        repository.raw_repository.autocrlf = true
      end

      it 'sets autocrlf to :input' do
        repository.update_autocrlf_option

        expect(repository.raw_repository.autocrlf).to eq(:input)
      end
    end

    describe 'when autocrlf is already set to :input' do
      before do
        repository.raw_repository.autocrlf = :input
      end

      it 'does nothing' do
        expect(repository.raw_repository).not_to receive(:autocrlf=).
          with(:input)

        repository.update_autocrlf_option
      end
    end
  end

  describe '#empty?' do
    let(:empty_repository) { create(:project_empty_repo).repository }

    it 'returns true for an empty repository' do
      expect(empty_repository.empty?).to eq(true)
    end

    it 'returns false for a non-empty repository' do
      expect(repository.empty?).to eq(false)
    end

    it 'caches the output' do
      expect(repository.raw_repository).to receive(:empty?).
        once.
        and_return(false)

      repository.empty?
      repository.empty?
    end
  end

  describe '#root_ref' do
    it 'returns a branch name' do
      expect(repository.root_ref).to be_an_instance_of(String)
    end

    it 'caches the output' do
      expect(repository.raw_repository).to receive(:root_ref).
        once.
        and_return('master')

      repository.root_ref
      repository.root_ref
    end
  end

  describe '#expire_cache' do
    it 'expires all caches' do
      expect(repository).to receive(:expire_branch_cache)

      repository.expire_cache
    end

    it 'expires the caches for a specific branch' do
      expect(repository).to receive(:expire_branch_cache).with('master')

      repository.expire_cache('master')
    end

    it 'expires the emptiness caches for an empty repository' do
      expect(repository).to receive(:empty?).and_return(true)
      expect(repository).to receive(:expire_emptiness_caches)

      repository.expire_cache
    end

    it 'does not expire the emptiness caches for a non-empty repository' do
      expect(repository).to receive(:empty?).and_return(false)
      expect(repository).not_to receive(:expire_emptiness_caches)

      repository.expire_cache
    end
  end

  describe '#expire_root_ref_cache' do
    it 'expires the root reference cache' do
      repository.root_ref

      expect(repository.raw_repository).to receive(:root_ref).
        once.
        and_return('foo')

      repository.expire_root_ref_cache

      expect(repository.root_ref).to eq('foo')
    end
  end

  describe '#expire_has_visible_content_cache' do
    it 'expires the visible content cache' do
      repository.has_visible_content?

      expect(repository).to receive(:branch_count).
        once.
        and_return(0)

      repository.expire_has_visible_content_cache

      expect(repository.has_visible_content?).to eq(false)
    end
  end

  describe '#expire_branch_cache' do
    # This method is private but we need it for testing purposes. Sadly there's
    # no other proper way of testing caching operations.
    let(:cache) { repository.send(:cache) }

    it 'expires the cache for all branches' do
      expect(cache).to receive(:expire).
        at_least(repository.branches.length).
        times

      repository.expire_branch_cache
    end

    it 'expires the cache for all branches when the root branch is given' do
      expect(cache).to receive(:expire).
        at_least(repository.branches.length).
        times

      repository.expire_branch_cache(repository.root_ref)
    end

    it 'expires the cache for a specific branch' do
      expect(cache).to receive(:expire).once

      repository.expire_branch_cache('foo')
    end
  end

  describe '#expire_emptiness_caches' do
    let(:cache) { repository.send(:cache) }

    it 'expires the caches' do
      expect(cache).to receive(:expire).with(:empty?)
      expect(repository).to receive(:expire_has_visible_content_cache)

      repository.expire_emptiness_caches
    end
  end

  describe :skip_merged_commit do
    subject { repository.commits(Gitlab::Git::BRANCH_REF_PREFIX + "'test'", limit: 100, skip_merges: true).map{ |k| k.id } }

    it { is_expected.not_to include('e56497bb5f03a90a51293fc6d516788730953899') }
  end

  describe '#merge' do
    it 'merges the code and return the commit id' do
      expect(merge_commit).to be_present
      expect(repository.blob_at(merge_commit.id, 'files/ruby/feature.rb')).to be_present
    end

    it 'sets the `in_progress_merge_commit_sha` flag for the given merge request' do
      merge_request = create(:merge_request, source_branch: 'feature', target_branch: 'master', source_project: project)
      merge_commit_id = repository.merge(user, merge_request, commit_options)
      repository.commit(merge_commit_id)

      expect(merge_request.in_progress_merge_commit_sha).to eq(merge_commit_id)
    end
  end

  describe '#revert' do
    let(:new_image_commit) { repository.commit('33f3729a45c02fc67d00adb1b8bca394b0e761d9') }
    let(:update_image_commit) { repository.commit('2f63565e7aac07bcdadb654e253078b727143ec4') }

    context 'when there is a conflict' do
      it 'aborts the operation' do
        expect(repository.revert(user, new_image_commit, 'master')).to eq(false)
      end
    end

    context 'when commit was already reverted' do
      it 'aborts the operation' do
        repository.revert(user, update_image_commit, 'master')

        expect(repository.revert(user, update_image_commit, 'master')).to eq(false)
      end
    end

    context 'when commit can be reverted' do
      it 'reverts the changes' do
        expect(repository.revert(user, update_image_commit, 'master')).to be_truthy
      end
    end

    context 'reverting a merge commit' do
      it 'reverts the changes' do
        merge_commit
        expect(repository.blob_at_branch('master', 'files/ruby/feature.rb')).to be_present

        repository.revert(user, merge_commit, 'master')
        expect(repository.blob_at_branch('master', 'files/ruby/feature.rb')).not_to be_present
      end
    end
  end

  describe '#cherry_pick' do
    let(:conflict_commit) { repository.commit('c642fe9b8b9f28f9225d7ea953fe14e74748d53b') }
    let(:pickable_commit) { repository.commit('7d3b0f7cff5f37573aea97cebfd5692ea1689924') }
    let(:pickable_merge) { repository.commit('e56497bb5f03a90a51293fc6d516788730953899') }

    context 'when there is a conflict' do
      it 'aborts the operation' do
        expect(repository.cherry_pick(user, conflict_commit, 'master')).to eq(false)
      end
    end

    context 'when commit was already cherry-picked' do
      it 'aborts the operation' do
        repository.cherry_pick(user, pickable_commit, 'master')

        expect(repository.cherry_pick(user, pickable_commit, 'master')).to eq(false)
      end
    end

    context 'when commit can be cherry-picked' do
      it 'cherry-picks the changes' do
        expect(repository.cherry_pick(user, pickable_commit, 'master')).to be_truthy
      end
    end

    context 'cherry-picking a merge commit' do
      it 'cherry-picks the changes' do
        expect(repository.blob_at_branch('master', 'foo/bar/.gitkeep')).to be_nil

        repository.cherry_pick(user, pickable_merge, 'master')
        expect(repository.blob_at_branch('master', 'foo/bar/.gitkeep')).not_to be_nil
      end
    end
  end

  describe '#before_delete' do
    describe 'when a repository does not exist' do
      before do
        allow(repository).to receive(:exists?).and_return(false)
      end

      it 'does not flush caches that depend on repository data' do
        expect(repository).not_to receive(:expire_cache)

        repository.before_delete
      end

      it 'flushes the tags cache' do
        expect(repository).to receive(:expire_tags_cache)

        repository.before_delete
      end

      it 'flushes the tag count cache' do
        expect(repository).to receive(:expire_tag_count_cache)

        repository.before_delete
      end

      it 'flushes the branches cache' do
        expect(repository).to receive(:expire_branches_cache)

        repository.before_delete
      end

      it 'flushes the branch count cache' do
        expect(repository).to receive(:expire_branch_count_cache)

        repository.before_delete
      end

      it 'flushes the root ref cache' do
        expect(repository).to receive(:expire_root_ref_cache)

        repository.before_delete
      end

      it 'flushes the emptiness caches' do
        expect(repository).to receive(:expire_emptiness_caches)

        repository.before_delete
      end

      it 'flushes the exists cache' do
        expect(repository).to receive(:expire_exists_cache).twice

        repository.before_delete
      end
    end

    describe 'when a repository exists' do
      before do
        allow(repository).to receive(:exists?).and_return(true)
      end

      it 'flushes the caches that depend on repository data' do
        expect(repository).to receive(:expire_cache)

        repository.before_delete
      end

      it 'flushes the tags cache' do
        expect(repository).to receive(:expire_tags_cache)

        repository.before_delete
      end

      it 'flushes the tag count cache' do
        expect(repository).to receive(:expire_tag_count_cache)

        repository.before_delete
      end

      it 'flushes the branches cache' do
        expect(repository).to receive(:expire_branches_cache)

        repository.before_delete
      end

      it 'flushes the branch count cache' do
        expect(repository).to receive(:expire_branch_count_cache)

        repository.before_delete
      end

      it 'flushes the root ref cache' do
        expect(repository).to receive(:expire_root_ref_cache)

        repository.before_delete
      end

      it 'flushes the emptiness caches' do
        expect(repository).to receive(:expire_emptiness_caches)

        repository.before_delete
      end
    end
  end

  describe '#before_change_head' do
    it 'flushes the branch cache' do
      expect(repository).to receive(:expire_branch_cache)

      repository.before_change_head
    end

    it 'flushes the root ref cache' do
      expect(repository).to receive(:expire_root_ref_cache)

      repository.before_change_head
    end
  end

  describe '#before_push_tag' do
    it 'flushes the cache' do
      expect(repository).to receive(:expire_cache)
      expect(repository).to receive(:expire_tag_count_cache)

      repository.before_push_tag
    end
  end

  describe '#before_import' do
    it 'flushes the emptiness cachess' do
      expect(repository).to receive(:expire_emptiness_caches)

      repository.before_import
    end

    it 'flushes the exists cache' do
      expect(repository).to receive(:expire_exists_cache)

      repository.before_import
    end
  end

  describe '#after_import' do
    it 'flushes the emptiness cachess' do
      expect(repository).to receive(:expire_emptiness_caches)

      repository.after_import
    end

    it 'flushes the exists cache' do
      expect(repository).to receive(:expire_exists_cache)

      repository.after_import
    end
  end

  describe '#after_push_commit' do
    it 'flushes the cache' do
      expect(repository).to receive(:expire_cache).with('master', '123')

      repository.after_push_commit('master', '123')
    end
  end

  describe '#after_create_branch' do
    it 'flushes the visible content cache' do
      expect(repository).to receive(:expire_has_visible_content_cache)

      repository.after_create_branch
    end
  end

  describe '#after_remove_branch' do
    it 'flushes the visible content cache' do
      expect(repository).to receive(:expire_has_visible_content_cache)

      repository.after_remove_branch
    end
  end

  describe '#after_create' do
    it 'flushes the exists cache' do
      expect(repository).to receive(:expire_exists_cache)

      repository.after_create
    end

    it 'flushes the root ref cache' do
      expect(repository).to receive(:expire_root_ref_cache)

      repository.after_create
    end

    it 'flushes the emptiness caches' do
      expect(repository).to receive(:expire_emptiness_caches)

      repository.after_create
    end
  end

  describe "#copy_gitattributes" do
    it 'returns true with a valid ref' do
      expect(repository.copy_gitattributes('master')).to be_truthy
    end

    it 'returns false with an invalid ref' do
      expect(repository.copy_gitattributes('invalid')).to be_falsey
    end
  end

  describe '#before_remove_tag' do
    it 'flushes the tag cache' do
      expect(repository).to receive(:expire_tag_count_cache)

      repository.before_remove_tag
    end
  end

  describe '#branch_count' do
    it 'returns the number of branches' do
      expect(repository.branch_count).to be_an_instance_of(Fixnum)
    end
  end

  describe '#tag_count' do
    it 'returns the number of tags' do
      expect(repository.tag_count).to be_an_instance_of(Fixnum)
    end
  end

  describe '#expire_branch_count_cache' do
    let(:cache) { repository.send(:cache) }

    it 'expires the cache' do
      expect(cache).to receive(:expire).with(:branch_count)

      repository.expire_branch_count_cache
    end
  end

  describe '#expire_tag_count_cache' do
    let(:cache) { repository.send(:cache) }

    it 'expires the cache' do
      expect(cache).to receive(:expire).with(:tag_count)

      repository.expire_tag_count_cache
    end
  end

  describe '#add_tag' do
    context 'with a valid target' do
      let(:user) { build_stubbed(:user) }

      it 'creates the tag using rugged' do
        expect(repository.rugged.tags).to receive(:create).
          with('8.5', repository.commit('master').id,
            hash_including(message: 'foo',
                           tagger: hash_including(name: user.name, email: user.email))).
          and_call_original

        repository.add_tag(user, '8.5', 'master', 'foo')
      end

      it 'returns a Gitlab::Git::Tag object' do
        tag = repository.add_tag(user, '8.5', 'master', 'foo')

        expect(tag).to be_a(Gitlab::Git::Tag)
      end
    end

    context 'with an invalid target' do
      it 'returns false' do
        expect(repository.add_tag(user, '8.5', 'bar', 'foo')).to be false
      end
    end
  end

  describe '#rm_branch' do
    let(:user) { create(:user) }

    it 'removes a branch' do
      expect(repository).to receive(:before_remove_branch)
      expect(repository).to receive(:after_remove_branch)

      repository.rm_branch(user, 'feature')
    end
  end

  describe '#rm_tag' do
    it 'removes a tag' do
      expect(repository).to receive(:before_remove_tag)
      expect(repository.rugged.tags).to receive(:delete).with('v1.1.0')

      repository.rm_tag('v1.1.0')
    end
  end

  describe '#avatar' do
    it 'returns nil if repo does not exist' do
      expect(repository).to receive(:exists?).and_return(false)

      expect(repository.avatar).to eq(nil)
    end

    it 'returns the first avatar file found in the repository' do
      expect(repository).to receive(:blob_at_branch).
        with('master', 'logo.png').
        and_return(true)

      expect(repository.avatar).to eq('logo.png')
    end

    it 'caches the output' do
      allow(repository).to receive(:blob_at_branch).
        with('master', 'logo.png').
        and_return(true)

      expect(repository.avatar).to eq('logo.png')

      expect(repository).not_to receive(:blob_at_branch)
      expect(repository.avatar).to eq('logo.png')
    end
  end

  describe '#expire_avatar_cache' do
    let(:cache) { repository.send(:cache) }

    before do
      allow(repository).to receive(:cache).and_return(cache)
    end

    context 'without a branch or revision' do
      it 'flushes the cache' do
        expect(cache).to receive(:expire).with(:avatar)

        repository.expire_avatar_cache
      end
    end

    context 'with a branch' do
      it 'does not flush the cache if the branch is not the default branch' do
        expect(cache).not_to receive(:expire)

        repository.expire_avatar_cache('cats')
      end

      it 'flushes the cache if the branch equals the default branch' do
        expect(cache).to receive(:expire).with(:avatar)

        repository.expire_avatar_cache(repository.root_ref)
      end
    end

    context 'with a branch and revision' do
      let(:commit) { double(:commit) }

      before do
        allow(repository).to receive(:commit).and_return(commit)
      end

      it 'does not flush the cache if the commit does not change any logos' do
        diff = double(:diff, new_path: 'test.txt')

        expect(commit).to receive(:raw_diffs).and_return([diff])
        expect(cache).not_to receive(:expire)

        repository.expire_avatar_cache(repository.root_ref, '123')
      end

      it 'flushes the cache if the commit changes any of the logos' do
        diff = double(:diff, new_path: Repository::AVATAR_FILES[0])

        expect(commit).to receive(:raw_diffs).and_return([diff])
        expect(cache).to receive(:expire).with(:avatar)

        repository.expire_avatar_cache(repository.root_ref, '123')
      end
    end
  end

  describe '#expire_exists_cache' do
    let(:cache) { repository.send(:cache) }

    it 'expires the cache' do
      expect(cache).to receive(:expire).with(:exists?)

      repository.expire_exists_cache
    end
  end

  describe '#build_cache' do
    let(:cache) { repository.send(:cache) }

    it 'builds the caches if they do not already exist' do
      cache_keys = repository.cache_keys + repository.cache_keys_for_branches_and_tags

      expect(cache).to receive(:exist?).
        exactly(cache_keys.length).
        times.
        and_return(false)

      cache_keys.each do |key|
        expect(repository).to receive(key)
      end

      repository.build_cache
    end

    it 'does not build any caches that already exist' do
      cache_keys = repository.cache_keys + repository.cache_keys_for_branches_and_tags

      expect(cache).to receive(:exist?).
        exactly(cache_keys.length).
        times.
        and_return(true)

      cache_keys.each do |key|
        expect(repository).not_to receive(key)
      end

      repository.build_cache
    end
  end

  describe "#keep_around" do
    it "does not fail if we attempt to reference bad commit" do
      expect(repository.kept_around?('abc1234')).to be_falsey
    end

    it "stores a reference to the specified commit sha so it isn't garbage collected" do
      repository.keep_around(sample_commit.id)

      expect(repository.kept_around?(sample_commit.id)).to be_truthy
    end

    it "attempting to call keep_around on truncated ref does not fail" do
      repository.keep_around(sample_commit.id)
      ref = repository.send(:keep_around_ref_name, sample_commit.id)
      path = File.join(repository.path, ref)
      # Corrupt the reference
      File.truncate(path, 0)

      expect(repository.kept_around?(sample_commit.id)).to be_falsey

      repository.keep_around(sample_commit.id)

      expect(repository.kept_around?(sample_commit.id)).to be_falsey

      File.delete(path)
    end
  end

  describe '#update_ref!' do
    it 'can create a ref' do
      repository.update_ref!('refs/heads/foobar', 'refs/heads/master', Gitlab::Git::BLANK_SHA)

      expect(repository.find_branch('foobar')).not_to be_nil
    end

    it 'raises CommitError when the ref update fails' do
      expect do
        repository.update_ref!('refs/heads/master', 'refs/heads/master', Gitlab::Git::BLANK_SHA)
      end.to raise_error(Repository::CommitError)
    end
  end
end
