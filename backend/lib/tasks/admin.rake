namespace :admin do
  desc "Create the admin account, or update it (new email, handle or password); asks for the password, never pass it as an argument"
  task create: :environment do
    require "io/console"

    ask = ->(prompt) { $stdout.print(prompt); $stdin.gets.to_s.strip }
    email = ENV["EMAIL"].presence || ask.("Email address: ")
    handle = ENV["HANDLE"].presence || ask.("Handle, as decisions will show it (human:<handle>): ")
    password = $stdin.getpass("Password (12 characters or more): ")

    # One admin: an existing account is updated (a new email doesn't add a
    # second administrator), and its sessions end, so a reset also signs out
    # anyone holding an old session.
    user = User.order(:id).first || User.new
    created = user.new_record?
    if user.update(email_address: email, handle:, password:)
      user.sessions.destroy_all unless created
      puts "#{created ? 'Created' : 'Updated'} #{user.email_address}. Decisions are recorded as #{user.actor}." \
        "#{' Existing sessions were signed out.' unless created}"
    else
      abort user.errors.full_messages.to_sentence
    end
  end
end
