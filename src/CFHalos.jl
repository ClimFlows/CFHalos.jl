module CFHalos

struct Halo{I<:Integer}
    other::Int # other rank involved in the exchange
    indices::Vector{I} # indices to send/receive
end

function on_halos(fun, halos)
    for halo in halos
        foreach(fun, halo.indices)
    end
end

function halo_buffers(data::AbstractVector, recv::Vector{<:Halo}, send::Vector{<:Halo})
    buffers(halos) = [similar(data, size(halo.indices)) for halo in halos]
    return buffers(recv), buffers(send)
end

function send_recv(MPI, comm, data_all, data_recv, data_send, recv, send)
    @assert length(data_recv) == length(recv)
    @assert length(data_send) == length(send)

    rank = MPI.Comm_rank(comm)

    # write into halos to be sent
    for (n, data) in enumerate(data_send)
        @assert length(data) == length(send[n].indices)
        for (j, index) in enumerate(send[n].indices)
            data[j] = data_all[index]
        end
    end

    # exchange halos
    send_reqs = [
        MPI.Isend(data, comm; dest = send[n].other, tag = rank) for
        (n, data) in enumerate(data_send)
    ]
    recv_reqs = [
        MPI.Irecv!(data, comm; source = recv[n].other, tag = recv[n].other) for
        (n, data) in enumerate(data_recv)
    ]
    MPI.Waitall(vcat(send_reqs, recv_reqs))

    # read from received halos
    for (n, data) in enumerate(data_recv)
        @assert length(data) == length(recv[n].indices)
        for (j, index) in enumerate(recv[n].indices)
            data_all[index] = data[j]
        end
    end
end

# extract halo information from DYNAMICO partitioned mesh file
function extract_halos(raw::AbstractVector{I}, pos=0) where {I<:Integer}
    function next()
        pos = pos+1
        return raw[pos]
    end

    halos = Halo{I}[]
    for _ in 1:next() # number of halos to receive
        halo = Halo(Int(next()), I[])
        for j in 1:next()
            push!(halo.indices, next()) # indices in the file are already 1-based
        end
        push!(halos, halo)
    end
    @assert pos == length(raw)
    return halos
end

end