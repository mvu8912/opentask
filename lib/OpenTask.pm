package OpenTask;
use strict;
use warnings;

use Dancer2;
use Data::UUID;
use File::Path qw(make_path);
use File::Copy qw(move);
use File::Spec;
use POSIX qw(strftime);
use YAML::XS qw(LoadFile Dump);

my $STORAGE_ROOT = $ENV{TASK_STORAGE_ROOT} // '/opentask';
my $USER_FILE    = $ENV{USER_FILE} // 'user.yml';

sub _respond {
    my ($data, $code) = @_;
    status($code) if defined $code;
    content_type 'text/yaml; charset=UTF-8';
    return Dump($data);
}

sub _timestamp {
    return strftime('%Y-%m-%dT%H:%M:%S', gmtime());
}

sub _compact_timestamp {
    return strftime('%Y%m%dT%H%M%S', gmtime());
}

sub _field {
    my ($hashref, @keys) = @_;
    for my $k (@keys) {
        return $hashref->{$k} if exists $hashref->{$k};
    }
    return;
}

sub _code_name_from_body {
    my ($payload) = @_;
    return _field($payload, 'code_name', 'code-name');
}

sub _code_name_from_query {
    return query_parameters->get('code_name') // query_parameters->get('code-name');
}

sub _load_users {
    return {} unless -e $USER_FILE;
    my $raw = eval { LoadFile($USER_FILE) };
    return {} if !$raw || ref($raw) ne 'HASH';
    my $users = $raw->{users};
    return {} if !$users || ref($users) ne 'HASH';
    return $users;
}

sub _validate_user {
    my ($username) = @_;
    return 0 if !defined $username || $username eq '';
    my $users = _load_users();
    return exists $users->{$username};
}

sub _app_dir {
    my ($code_name) = @_;
    return File::Spec->catdir($STORAGE_ROOT, $code_name);
}

sub _status_dir {
    my ($code_name, $status) = @_;
    return File::Spec->catdir(_app_dir($code_name), $status);
}

sub _ensure_dirs {
    my ($code_name) = @_;
    make_path(_status_dir($code_name, 'tasks'));
    make_path(_status_dir($code_name, 'done'));
}

sub _task_file {
    my (%args) = @_;
    return File::Spec->catfile(
        _status_dir($args{code_name}, $args{status}),
        "$args{stamp}-$args{uuid}.md",
    );
}

sub _parse_filename {
    my ($path) = @_;
    my ($file) = $path =~ m{([^/]+)$};
    return unless $file;
    my ($stamp, $uuid) = $file =~ /^([0-9]{8}T[0-9]{6})-(.+)\.md$/;
    return unless $stamp && $uuid;
    return ($stamp, $uuid);
}

sub _read_task_file {
    my ($path, $status) = @_;
    open my $fh, '<', $path or return;
    local $/;
    my $content = <$fh> // '';
    close $fh;

    my ($stamp, $uuid) = _parse_filename($path);
    return unless $uuid;

    my ($title) = $content =~ /^Title:\s*(.*)$/m;
    my ($version) = $content =~ /^Version:\s*(\d+)$/m;
    my ($timestamp) = $content =~ /^Timestamp:\s*(.*)$/m;
    my ($username) = $content =~ /^Username:\s*(.*)$/m;
    my ($details) = $content =~ /\n\n(.*)\z/s;

    $title //= '';
    $version //= 1;
    $timestamp //= _timestamp();
    $username //= '';
    $details //= '';

    return {
        id        => $uuid,
        stamp     => $stamp,
        title     => $title,
        version   => 0 + $version,
        timestamp => $timestamp,
        username  => $username,
        details   => $details,
        status    => $status,
        path      => $path,
    };
}

sub _write_task_version {
    my (%args) = @_;
    my $path = _task_file(
        code_name => $args{code_name},
        status    => $args{status},
        stamp     => $args{stamp},
        uuid      => $args{uuid},
    );

    open my $fh, '>', $path or die "Cannot write $path: $!";
    print {$fh} "Title: $args{title}\n";
    print {$fh} "Task-ID: $args{uuid}\n";
    print {$fh} "Username: $args{username}\n";
    print {$fh} "Version: $args{version}\n";
    print {$fh} "Timestamp: $args{timestamp}\n\n";
    print {$fh} $args{details};
    close $fh;

    return $path;
}

sub _all_entries {
    my ($code_name) = @_;
    _ensure_dirs($code_name);

    my @entries;
    for my $status (qw(tasks done)) {
        my $dir = _status_dir($code_name, $status);
        opendir my $dh, $dir or next;
        while (my $file = readdir $dh) {
            next if $file =~ /^\./;
            next if $file !~ /\.md$/;
            my $path = File::Spec->catfile($dir, $file);
            my $entry = _read_task_file($path, $status eq 'tasks' ? 'new' : 'done');
            push @entries, $entry if $entry;
        }
        closedir $dh;
    }

    return \@entries;
}

sub _latest_by_uuid {
    my ($code_name, $uuid) = @_;
    my $entries = _all_entries($code_name);
    my @versions = grep { $_->{id} eq $uuid } @{$entries};
    return unless @versions;

    @versions = sort {
        $a->{stamp} cmp $b->{stamp} || $a->{version} <=> $b->{version}
    } @versions;

    my $latest = $versions[-1];
    $latest->{all_versions} = \@versions;
    return $latest;
}

sub _normalize_status_dir {
    my ($status) = @_;
    return $status eq 'done' ? 'done' : 'tasks';
}

sub _validate_status {
    my ($status) = @_;
    return 1 if !defined $status;
    return $status eq 'new' || $status eq 'done';
}

post '/tasks' => sub {
    my $payload = body_parameters->as_hashref;

    my $username = $payload->{username};
    my $code_name = _code_name_from_body($payload);
    my $title   = $payload->{title};
    my $details = $payload->{details};

    if (!$username || !$code_name || !$title || !defined $details) {
        return _respond({ error => 'username, code-name, title, and details are required' }, 400);
    }

    if (!_validate_user($username)) {
        return _respond({ error => 'username is invalid or not found in user.yml' }, 403);
    }

    _ensure_dirs($code_name);

    my $uuid = Data::UUID->new->create_str();
    my $now  = _timestamp();
    my $stamp = _compact_timestamp();

    _write_task_version(
        code_name => $code_name,
        status    => 'tasks',
        stamp     => $stamp,
        uuid      => $uuid,
        username  => $username,
        title     => $title,
        version   => 1,
        timestamp => $now,
        details   => $details,
    );

    return _respond([$uuid], 201);
};

put '/tasks/:id' => sub {
    my $task_id  = route_parameters->get('id');
    my $payload  = body_parameters->as_hashref;
    my $username = $payload->{username};
    my $code_name = _code_name_from_body($payload);
    my $details  = $payload->{details};

    if (!$username || !$code_name || !defined $details) {
        return _respond({ error => 'username, code-name, and details are required' }, 400);
    }

    if (!_validate_user($username)) {
        return _respond({ error => 'username is invalid or not found in user.yml' }, 403);
    }

    my $latest = _latest_by_uuid($code_name, $task_id);
    if (!$latest) {
        return _respond({ error => 'task not found' }, 404);
    }

    my $now = _timestamp();
    my $stamp = _compact_timestamp();
    my $new_version = $latest->{version} + 1;
    my $status_dir = _normalize_status_dir($latest->{status});

    _write_task_version(
        code_name => $code_name,
        status    => $status_dir,
        stamp     => $stamp,
        uuid      => $task_id,
        username  => $username,
        title     => $latest->{title},
        version   => $new_version,
        timestamp => $now,
        details   => $details,
    );

    return _respond({
        id      => $task_id,
        message => "task $latest->{title} has been updated, continue working until finish the whole task please.",
    }, 200);
};

get '/tasks/:id' => sub {
    my $task_id = route_parameters->get('id');
    my $username = query_parameters->get('username');
    my $code_name  = _code_name_from_query();

    if (!$username || !$code_name) {
        return _respond({ error => 'username and code-name are required' }, 400);
    }

    if (!_validate_user($username)) {
        return _respond({ error => 'username is invalid or not found in user.yml' }, 403);
    }

    my $latest = _latest_by_uuid($code_name, $task_id);
    if (!$latest) {
        return _respond({ error => 'task not found' }, 404);
    }

    return _respond({
        id         => $latest->{id},
        username   => $latest->{username},
        'code-name'=> $code_name,
        title      => $latest->{title},
        status     => $latest->{status},
        details    => $latest->{details},
        version    => $latest->{version},
        timestamp  => $latest->{timestamp},
    }, 200);
};

get '/tasks' => sub {
    my $username = query_parameters->get('username');
    my $code_name = _code_name_from_query();
    my $status_filter = query_parameters->get('status');
    my $from = query_parameters->get('from');
    my $to = query_parameters->get('to');
    my $search = query_parameters->get('search');

    if (!$username || !$code_name) {
        return _respond({ error => 'username and code-name are required' }, 400);
    }

    if (!_validate_user($username)) {
        return _respond({ error => 'username is invalid or not found in user.yml' }, 403);
    }

    if (!_validate_status($status_filter)) {
        return _respond({ error => 'status must be new or done when provided' }, 400);
    }

    my $entries = _all_entries($code_name);
    my %latest;
    for my $entry (@{$entries}) {
        my $id = $entry->{id};
        if (!$latest{$id}
            || $latest{$id}{stamp} lt $entry->{stamp}
            || ($latest{$id}{stamp} eq $entry->{stamp} && $latest{$id}{version} < $entry->{version})) {
            $latest{$id} = $entry;
        }
    }

    my @tasks = sort { $a->{timestamp} cmp $b->{timestamp} } values %latest;

    @tasks = grep {
        my $t = $_;
        (!$status_filter || $t->{status} eq $status_filter)
            && (!$from || $t->{timestamp} ge $from)
            && (!$to || $t->{timestamp} le $to)
            && (!$search || $t->{title} =~ /\Q$search\E/i || $t->{details} =~ /\Q$search\E/i)
    } @tasks;

    my (@todo, @done);
    for my $task (@tasks) {
        my $record = {
            'task-id' => $task->{id},
            details   => $task->{details},
            timestamp => $task->{timestamp},
            username  => $task->{username},
        };
        if ($task->{status} eq 'done') {
            push @done, $record;
        } else {
            push @todo, $record;
        }
    }

    return _respond({
        'Task Needs To Be Done' => \@todo,
        'Completed Tasks'       => \@done,
    }, 200);
};

post '/tasks/:id/done' => sub {
    my $task_id  = route_parameters->get('id');
    my $payload  = body_parameters->as_hashref;
    my $username = $payload->{username};
    my $code_name = _code_name_from_body($payload);

    if (!$username || !$code_name) {
        return _respond({ error => 'username and code-name are required' }, 400);
    }

    if (!_validate_user($username)) {
        return _respond({ error => 'username is invalid or not found in user.yml' }, 403);
    }

    my $latest = _latest_by_uuid($code_name, $task_id);
    if (!$latest) {
        return _respond({ error => 'task not found' }, 404);
    }

    for my $v (@{$latest->{all_versions}}) {
        my ($stamp, $uuid) = _parse_filename($v->{path});
        my $target = _task_file(
            code_name => $code_name,
            status    => 'done',
            stamp     => $stamp,
            uuid      => $uuid,
        );
        next if $v->{path} eq $target;
        move($v->{path}, $target);
    }

    my $refreshed = _latest_by_uuid($code_name, $task_id);
    my $done_ts = _timestamp();
    my $done_stamp = _compact_timestamp();

    _write_task_version(
        code_name => $code_name,
        status    => 'done',
        stamp     => $done_stamp,
        uuid      => $task_id,
        username  => $username,
        title     => $refreshed->{title},
        version   => $refreshed->{version} + 1,
        timestamp => $done_ts,
        details   => $refreshed->{details},
    );

    my $entries = _all_entries($code_name);
    my %latest_new;
    for my $e (@{$entries}) {
        next if $e->{id} eq $task_id;
        next unless $e->{status} eq 'new';
        if (!$latest_new{$e->{id}} || $latest_new{$e->{id}}{stamp} lt $e->{stamp}) {
            $latest_new{$e->{id}} = $e;
        }
    }
    my @next = sort { $a->{timestamp} cmp $b->{timestamp} } values %latest_new;

    if (@next) {
        return _respond({
            'this-task' => $task_id,
            message     => "task $latest->{title} is completed, move on to the next task $next[0]->{id}",
            'next-task' => $next[0]->{id},
        }, 200);
    }

    return _respond({
        'this-task' => $task_id,
        message     => "task $latest->{title} is completed. You have done all your tasks. Well done",
    }, 200);
};

true;
