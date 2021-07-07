# The Little Elixir & OTP Guidebook

This is my repo with the implementation of examples from "The Little Elixir & OTP Guidebook".

I'm learning elixir ([more on that here](http://willcodeforskipass.com/blog/im-gonna-learn-elixir-again/)) and I'm following this book to grasp fundamentals.
Originally I didn't plan on doing this repository, however, I found that the biggest example in the book (the worker pool application from chapter 6 and 7) is... not working as intended if you follow the book.

Note: I'm using the "The Little Elixir & OTP Guidebook - corrected 9182019" version. (ISBN 9781633430112)

Note #2: I'm aware that you would probably not want to implement a worker pool this way.
You wouldn't even want to implement a worker pool on your own, I'm perfectly aware there must be tons of good implementations out there already.
This is an exercise to learn elixir and OTP primitives and we should treat it as such.

## The application goal (as defined in the book)

The application is an ordinary worker pool application that allows checking out and checking in worker processes by consumers.
On start, each pool starts its configured number of workers.
It also keeps track of checked out workers and if any worker or consumer stops, it restores the pool to its configured size.

Additionally, in the last version of the application, it allows for a pre-configured overflow of workers - if there is too many consumers checking out workers, it allows a temporary bigger size of worker pool.
For this scenario, if the overflow workers are checked in or they (or their consumer) stop unexpectedly, they are discarded and the pool goes back to its intended 'size'.

The application is introduced in versions in the book:
> 1	Supports a single pool Supports a fixed number of workers. No recovery when consumer and/or worker processes fail.
>
> 2	Supports a single pool Supports a fixed number of workers. Recovery when consumer and/or worker processes fail.
>
> 3	Supports multiple pools Supports a variable number of workers.
>
> 4	Supports multiple pools Supports a variable number of workers. Variable-sized pool allows for worker overflow. Queuing for consumer processes when all workers are busy.


## Problems

### Problem numero uno:

In the book, the logic of keeping the worker pool size and tracking overflow etc. is extracted to a _GenServer_ - type _Module_ (`PoolServer`).
The `PoolServer` uses a _Supervisor_ (`PoolWorkerSupervisor`) to dynamically spawn workers.
`PoolServer` and `PoolWorkerSupervisor` are linked together and are supervised by another supervisor with _:one_for_all_ restart strategy so that if `PoolServer` or `PoolWorkerSupervisor` stop, both are recreated with a fresh worker pool.

This separation introduces 1 major issue.
The actual `PoolServer` (even though it traps exits) is unaware of _:EXIT_ messages from workers.
Because of that:
- either you set worker _:restart_ as _:permanent_ - in which case every worker will be restarted on exit. **this includes the workers created a spart of the _overflow_**, so the worker pool will grow
- or you set worker _:restart_ as _:temporary_ - in this case when worker stops, it will not be restarted by the `PoolWorkerSupervisor`, but `PoolServer` has no way of knowing it should recreate the worker

### Problem numero dos

`PoolServer` does not handle worker exit correctly, even assuming the first problem is resolved.
If the worker exits, only the overlfow/consumer logic is handled.
The `workers` collection in the state is not touched unless it is to add a new worker.
This is because an implicit assumption is made that only a checked out worker will fail.

> I'm not sure if this is actually a 'problem' or a design choice, but since it is not stated anywhere explicitly, I assume this is a bug (?)
>
> Also... maybe it's just me being paranoid and overly defensive?
> It would be safe to let the worker fail if we were using a _Supervisor_ to handle its restart, but here we are essentially supervising the workers ourselves, so it smells like an omission

Word-for-word implementation from the book  (including both errors above, with workers setup to with _:permanent_ restart strategy) is present on branch [`the-book-implementation`](https://github.com/tarnas14/the-little-elixir-and-otp-guidebook/tree/the-book-implementation).

Below I discuss the solutions for the first problem, because the second one is trivial to handle.

## Solutions

In order of things I thought of and tried

### Link the workers with the `PoolServer`

Branch: [`link-workers-to-poolserver`](https://github.com/tarnas14/the-little-elixir-and-otp-guidebook/tree/link-workers-to-poolserver)

In this [not elegant?] solution,
- workers are set as _:temporary_, so supervisor doesn't restart them (so what's the point of the supervisor, eh?)
- each worker is passed their respective `PoolServer` pid and on init link themselves to the `PoolServer`.

This way, `PoolServer` is notified when worker dies and is able to react to it, reconcile the pool state and everything works well.

At first glance this **isn't** an elegant solution because it takes a step back from the `PoolServer` - `PoolWorkerSupervisor` separation.
We could basically merge them together at this point, and have the `PoolServer` as supervisor with additional logic.
The coupling of `PoolServer` and workers doesn't look nice - even in the _:observer_, the lines indicating links between them look suspicious...
Especially when you consider that "link" in processes means that they should be considered together when they stop and here it is used only to listen for _:EXIT_.

Which brings us to:

### Have the `PoolServer` monitor the workers

Branch: [`monitor-the-workers`](https://github.com/tarnas14/the-little-elixir-and-otp-guidebook/tree/monitor-the-workers)

In this we are (I think) using the more applicable primitive of the language - _monitoring_.
We removed the coupling between `PoolServer` and workers and it gives me great joy, because now workers do not care what they are managed by.

We had to introduce more state for worker and store the monitor reference, but this is a small cost, imo.
