require File.expand_path("../rsync/version", __FILE__)

Rake::Task["deploy:check"].enhance ["rsync:hook_scm"]
Rake::Task["deploy:updating"].enhance ["rsync:hook_scm"]

desc "Stage and rsync to the server (or its cache)."
task :rsync => %w[rsync:stage] do
  roles(:all).each do |role|
    user = role.user + "@" if !role.user.nil?
    options = "#{fetch(:rsync_options).join(' ')}"
    from = "#{fetch(:rsync_stage)}/"
    to = "#{user}#{role.hostname}:#{fetch(:rsync_cache_path) || release_path}"
    `rsync #{options} #{from} #{to}`
  end
end

namespace :rsync do
  # NOTE: Please don't depend on tasks without a description (`desc`) as they
  # might change between minor or patch version releases. They make up the
  # private API and internals of Capistrano::Rsync. If you think something should
  # be public for extending and hooking, please let me know!

  fetch(:rsync_options) do
    set :rsync_options, []
  end
  fetch(:rsync_copy) do
    set :rsync_copy, "rsync --archive --acls --xattrs"
  end

  # Stage is used on your local machine for rsyncing from.
  fetch(:rsync_stage) do
    set :rsync_stage, "tmp/deploy"
  end

  # Cache is used on the server to copy files to from to the release directory.
  # Saves you rsyncing your whole app folder each time.  If you nil rsync_cache,
  # Capistrano::Rsync will sync straight to the release path.
  fetch(:rsync_cache) do
    set :rsync_cache, "shared/deploy"
  end

  set :rsync_cache_path, -> {
    cache = fetch(:rsync_cache)
    cache = "#{deploy_to}/#{cache}" if cache && cache !~ /^\//
    cache
  }

  task :hook_scm do
    Rake::Task.define_task("#{scm}:check") do
      invoke "rsync:check"
    end

    Rake::Task.define_task("#{scm}:create_release") do
      invoke "rsync:release"
    end
  end

  task :check do
    # Everything's a-okay inherently!
  end

  task :create_stage do
    next if File.directory?(fetch(:rsync_stage))
    `git clone #{fetch(:repo_url, ".")} #{fetch(:rsync_stage)}`
  end

  desc "Stage the repository in a local directory."
  task :stage => %w[create_stage] do
    Dir.chdir fetch(:rsync_stage) do
      `git fetch --quiet --all --prune`
      `git reset --hard origin/#{fetch(:branch)}`
      set :current_revision, "#{`git rev-parse --short HEAD`}".chomp
    end
  end

  desc "Copy the code to the releases directory."
  task :release => %w[rsync] do
    # Skip copying if we've already synced straight to the release directory.
    next if !fetch(:rsync_cache)

    copy = %(#{fetch(:rsync_copy)} "#{fetch(:rsync_cache_path)}/" "#{release_path}/")
    on roles(:all).each do execute copy end
  end

  # Matches the naming scheme of git tasks.
  # Plus was part of the public API in Capistrano::Rsync <= v0.2.1.
  task :create_release => %w[release]
end
