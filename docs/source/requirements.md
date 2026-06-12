# Requirements

In order to test this design on hardware, you will need the following:

* Vivado 2025.2
* Vitis 2025.2 (for the bare-metal echo server)
* PetaLinux Tools 2025.2
* [Quad SFP28 FMC]
* [AMD Versal Integrated MRMAC License](https://www.amd.com/en/products/adaptive-socs-and-fpgas/intellectual-property/mrmac.html)
  (a free, no-cost license is required to generate a bitstream that uses the integrated MRMAC)
* One of the supported carrier boards listed below
* SFP+/SFP28 modules or DACs, or SFP28 passive loopback modules for the bundled self-test

## List of supported boards

{% for group in data.groups %}
{% set boards = {} %}
{% for design in data.designs %}{% if design.publish and design.group == group.label %}
{% if design.board not in boards %}{% set _ = boards.update({design.board: {"link": design.link, "connectors": []}}) %}{% endif %}
{% if design.connector not in boards[design.board]["connectors"] %}{% set _ = boards[design.board]["connectors"].append(design.connector) %}{% endif %}
{% endif %}{% endfor %}
{% if boards | length > 0 %}
### {{ group.name }} boards

| Carrier board        | Supported FMC connector(s)    |
|---------------------|--------------|
{% for name, board in boards.items() %}| [{{ name }}]({{ board.link }}) | {% for connector in board.connectors %}{{ connector }} {% endfor %} |
{% endfor %}
{% endif %}
{% endfor %}

For the list of target designs showing the supported link speeds, refer to the
[build instructions](build_instructions).

[Quad SFP28 FMC]: https://docs.opsero.com/op081/datasheet/overview/
