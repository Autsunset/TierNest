// Share duplicate reads, supersede requests for a different target, and let callers
// reject stale results. Invalidation never pretends to cancel the root command.
export class LatestRequest {
  current = null;

  run(key, work, { force = false } = {}) {
    if (!force && this.current?.key === key) return this.current.promise;
    const request = { key, promise: null };
    this.current = request;
    request.promise = Promise.resolve()
      .then(() => this.current === request ? work(() => this.current === request) : undefined)
      .finally(() => { if (this.current === request) this.current = null; });
    return request.promise;
  }

  invalidate() { this.current = null; }
}
