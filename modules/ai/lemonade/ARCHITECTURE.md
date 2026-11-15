# Lemonade

The module declares Python for Lemonade's ROCm wheel installer. Arch's Python
package supplies `venv` and its bundled pip; Lemonade owns the downloaded ROCm
runtime and backend binaries. The AMD GPU module supplies the Vulkan driver.
