"""Replace generated PNGs atomically, tolerating short sync-folder locks."""
import os
import tempfile
import time
from pathlib import Path


def save_png_atomic(image, destination):
    destination = Path(destination)
    descriptor, temporary = tempfile.mkstemp(prefix=".qq-image-", suffix=".asset-tmp", dir=destination.parent)
    os.close(descriptor)
    try:
        image.save(temporary, format="PNG")
        for attempt in range(8):
            try:
                os.replace(temporary, destination)
                break
            except OSError:
                if attempt == 7:
                    raise
                time.sleep(.05 * (attempt + 1))
    finally:
        Path(temporary).unlink(missing_ok=True)
