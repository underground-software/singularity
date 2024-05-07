import coverage
cov = coverage.Coverage(data_file='/tmp/coverage',data_suffix=True)
cov.start()
import radius
cov.stop()
cov.save()

def application(env, SR):
    cov = coverage.Coverage(data_file='/tmp/coverage',data_suffix=True)
    cov.start()
    out = radius.application(env, SR)
    cov.stop()
    cov.save()
    return out
