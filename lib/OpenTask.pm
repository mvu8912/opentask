package OpenTask;
use strict;
use warnings;

use Dancer2;
use Data::UUID;
use File::Basename qw(dirname);
use File::Path qw(make_path);
use JSON qw(decode_json encode_json);
use POSIX qw(strftime);

set serializer => 'JSON';

my $STORAGE_FILE = $ENV{TASK_STORAGE_FILE} // 'data/tasks.json';

sub _timestamp {
    return strftime('%Y-%m-%dT%H:%M:%S', gmtime());
}

sub _read_storage {
    return { apps => {} } unless -e $STORAGE_FILE;

    open my $fh, '<', $STORAGE_FILE or die "Cannot open $STORAGE_FILE: $!";
    local $/;
    my $raw = <$fh> // '{}';
    close $fh;

    my $decoded = eval { decode_json($raw) };
    return { apps => {} } if !$decoded || ref($decoded) ne 'HASH';

    $decoded->{apps} //= {};
    return $decoded;
}

sub _write_storage {
    my ($data) = @_;

    my $dir = dirname($STORAGE_FILE);
    make_path($dir) if !-d $dir;

    open my $fh, '>', $STORAGE_FILE or die "Cannot write $STORAGE_FILE: $!";
    print {$fh} encode_json($data);
    close $fh;
}

sub _latest_version {
    my ($task) = @_;
    return $task->{versions}->[-1];
}

sub _validate_status {
    my ($status) = @_;
    return 1 if !defined $status;
    return $status eq 'new' || $status eq 'done';
}

post '/tasks' => sub {
    my $payload = body_parameters->as_hashref;

    my $app_id  = $payload->{app_id};
    my $title   = $payload->{title};
    my $details = $payload->{details};

    if (!$app_id || !$title || !defined $details) {
        status 400;
        return { error => 'app_id, title, and details are required' };
    }

    my $store = _read_storage();
    $store->{apps}{$app_id} //= { tasks => {} };

    my $uuid = Data::UUID->new->create_str();
    my $now  = _timestamp();

    $store->{apps}{$app_id}{tasks}{$uuid} = {
        id         => $uuid,
        title      => $title,
        status     => 'new',
        created_at => $now,
        updated_at => $now,
        versions   => [
            {
                version   => 1,
                details   => $details,
                timestamp => $now,
            }
        ],
    };

    _write_storage($store);

    status 201;
    return [$uuid];
};

put '/tasks/:id' => sub {
    my $task_id  = route_parameters->get('id');
    my $payload  = body_parameters->as_hashref;
    my $app_id   = $payload->{app_id};
    my $details  = $payload->{details};

    if (!$app_id || !defined $details) {
        status 400;
        return { error => 'app_id and details are required' };
    }

    my $store = _read_storage();
    my $task  = $store->{apps}{$app_id}{tasks}{$task_id};

    if (!$task) {
        status 404;
        return { error => 'task not found' };
    }

    my $now = _timestamp();
    my $version = scalar @{$task->{versions}};

    push @{$task->{versions}}, {
        version   => $version + 1,
        details   => $details,
        timestamp => $now,
    };

    $task->{updated_at} = $now;

    _write_storage($store);

    return {
        id      => $task_id,
        message => "task $task->{title} has been updated, continue working until finish the whole task please.",
    };
};

get '/tasks/:id' => sub {
    my $task_id = route_parameters->get('id');
    my $app_id  = query_parameters->get('app_id');

    if (!$app_id) {
        status 400;
        return { error => 'app_id is required' };
    }

    my $store = _read_storage();
    my $task  = $store->{apps}{$app_id}{tasks}{$task_id};

    if (!$task) {
        status 404;
        return { error => 'task not found' };
    }

    my $latest = _latest_version($task);

    return {
        id         => $task->{id},
        app_id     => $app_id,
        title      => $task->{title},
        status     => $task->{status},
        details    => $latest->{details},
        version    => $latest->{version},
        timestamp  => $latest->{timestamp},
        created_at => $task->{created_at},
        updated_at => $task->{updated_at},
    };
};

get '/tasks' => sub {
    my $app_id = query_parameters->get('app_id');
    my $status_filter = query_parameters->get('status');
    my $from = query_parameters->get('from');
    my $to = query_parameters->get('to');
    my $search = query_parameters->get('search');

    if (!$app_id) {
        status 400;
        return { error => 'app_id is required' };
    }

    if (!_validate_status($status_filter)) {
        status 400;
        return { error => 'status must be new or done when provided' };
    }

    my $store = _read_storage();
    my $tasks = $store->{apps}{$app_id}{tasks} // {};

    my @entries = sort { $a->{updated_at} cmp $b->{updated_at} } values %{$tasks};

    @entries = grep {
        my $t = $_;
        (!$status_filter || $t->{status} eq $status_filter)
            && (!$from || $t->{updated_at} ge $from)
            && (!$to || $t->{updated_at} le $to)
            && (!$search || $t->{title} =~ /\Q$search\E/i || _latest_version($t)->{details} =~ /\Q$search\E/i)
    } @entries;

    my (@todo, @done);
    for my $task (@entries) {
        my $latest = _latest_version($task);
        my $record = {
            'task-id'   => $task->{id},
            details     => $latest->{details},
            timestamp   => $latest->{timestamp},
        };
        if ($task->{status} eq 'done') {
            push @done, $record;
        } else {
            push @todo, $record;
        }
    }

    return {
        'Task Needs To Be Done' => \@todo,
        'Completed Tasks'       => \@done,
    };
};

post '/tasks/:id/done' => sub {
    my $task_id  = route_parameters->get('id');
    my $payload  = body_parameters->as_hashref;
    my $app_id   = $payload->{app_id};

    if (!$app_id) {
        status 400;
        return { error => 'app_id is required' };
    }

    my $store = _read_storage();
    my $tasks = $store->{apps}{$app_id}{tasks};
    my $task  = $tasks->{$task_id};

    if (!$task) {
        status 404;
        return { error => 'task not found' };
    }

    $task->{status} = 'done';
    $task->{updated_at} = _timestamp();
    $task->{completed_at} = $task->{updated_at};

    my @next = sort { $a->{created_at} cmp $b->{created_at} }
        grep { $_->{status} eq 'new' && $_->{id} ne $task_id } values %{$tasks};

    _write_storage($store);

    if (@next) {
        return {
            'this-task' => $task_id,
            message     => "task $task->{title} is completed, move on to the next task $next[0]->{id}",
            'next-task' => $next[0]->{id},
        };
    }

    return {
        'this-task' => $task_id,
        message     => "task $task->{title} is completed. You have done all your tasks. Well done",
    };
};

true;
