# CFHalos

[![Dev](https://img.shields.io/badge/docs-dev-blue.svg)](https://ClimFlows.github.io/CFHalos.jl/dev/)
[![Build Status](https://github.com/ClimFlows/CFHalos.jl/actions/workflows/CI.yml/badge.svg?branch=main)](https://github.com/ClimFlows/CFHalos.jl/actions/workflows/CI.yml?query=branch%3Amain)
[![Coverage](https://codecov.io/gh/ClimFlows/CFHalos.jl/branch/main/graph/badge.svg)](https://codecov.io/gh/ClimFlows/CFHalos.jl)

CFHalos is a Julia package designed for managing halo exchanges in distributed memory parallel computing environments. It provides utilities for handling data communication between processors when working with domain decomposition methods, particularly useful in climate and weather modeling applications.

## Overview

The package implements core functionality for managing halo regions in distributed computing scenarios. Halo regions are data that needs to be exchanged between neighboring computational domains to maintain consistency during computations.

Key features include:
- Definition of `Halo` structures for representing communication patterns
- Functions for iterating over halo regions (`on_halos`)
- Buffer management for sending and receiving halo data (`halo_buffers`)
- MPI-based communication routines for exchanging halo data (`send_recv`)

## Installation

To install CFHalos, run the following in Julia:

```julia
using Pkg
Pkg.add("CFHalos")
```

Or in the package manager mode:

```julia
] add CFHalos
```

## Usage

Here's a basic example of how to use CFHalos:

```julia
using CFHalos
using MPI

# Define halo regions
halo1 = Halo(2, [1, 2, 3])
halo2 = Halo(1, [4, 5, 6])

# Apply a function to all halo indices
on_halos(x -> println("Processing index: ", x), [halo1, halo2])

# Create buffers for communication
data = [1.0, 2.0, 3.0, 4.0, 5.0, 6.0]
recv_halo = [halo1]
send_halo = [halo2]
recv_buffers, send_buffers = halo_buffers(data, recv_halo, send_halo)
```

## Using with DYNAMICO Meshes

CFHalos is designed to work with DYNAMICO partitioned meshes. The package provides the core functionality for halo exchanges, and includes the `extract_halos` function for parsing halo information from DYNAMICO mesh files.

To use CFHalos with DYNAMICO meshes:

1. First, obtain a DYNAMICO mesh file using ClimFlowsData:
```julia
using ClimFlowsData
pmesh = VoronoiLowRes("mesh4deg.16.nc")  # or another mesh file
```

2. Define helper functions to read data from mesh files and use CFHalos to parse halo information:
```julia
using CFHalos: Halo, on_halos, halo_buffers, send_recv, extract_halos
using NetCDF
using MPI

# Helper functions to read from mesh files (these are typically defined in test files)
pget(MPI, pmesh, var) = MPI.Critical() do
    slice(MPI.Comm_rank(MPI.COMM_WORLD), NetCDF.open(pmesh, var))
end

pget(MPI, pmesh, num, var) = MPI.Critical() do
    rank = MPI.Comm_rank(MPI.COMM_WORLD)
    n = slice(rank, NetCDF.open(pmesh, num)) :: Int32
    return slice(rank, n, NetCDF.open(pmesh, var))
end

slice(rank, array::AbstractVector) = array[rank+1]
slice(rank, n, array::AbstractMatrix) = array[1:n, rank+1]

# Read halo data from mesh file using CFHalos.extract_halos
primal_recv = extract_halos(pget(MPI, pmesh, "primal_recv_num", "primal_recv"))
primal_send = extract_halos(pget(MPI, pmesh, "primal_send_num", "primal_send"))
```

3. Prepare buffers and perform halo exchanges:
```julia
# Get data arrays from mesh
Ai = pget(MPI, pmesh, "primal_num", "Ai")

# Preallocate buffers
Ai_recv, Ai_send = halo_buffers(Ai, primal_recv, primal_send)

# Compute something
Ai2 = Ai .* Ai 

# Erase halo values
on_halos(primal_recv) do ij
    Ai2[ij] = 0 
end

# Exchange halos
send_recv(MPI, comm, Ai2, Ai_recv, Ai_send, primal_recv, primal_send)

# Verify results
@assert Ai2 ≈ (Ai .* Ai)
```

## Package Structure

- `Halo`: Struct representing a halo region with neighbor rank and indices
- `on_halos`: Function to apply operations to all halo indices
- `halo_buffers`: Function to create buffers for halo data exchange
- `send_recv`: Function to perform actual MPI communication of halo data
- `split_halos`: Function to parse halo information from DYNAMICO mesh files

## Contributing

Contributions are welcome! Please feel free to submit a Pull Request.

## License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.