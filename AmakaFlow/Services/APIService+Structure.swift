//
//  APIService+Structure.swift
//  AmakaFlow
//
//  AMA-2305 — live BFF structure suggest / apply (ADR-017 / AMA-2306).
//  POST /v1/ingest/structure/suggest|apply
//

import Foundation

extension APIService {
    /// POST `/v1/ingest/structure/suggest`
    func suggestStructure(text: String, source: String? = nil) async throws -> StructureSuggestResult {
        let body = StructureSuggestRequest(text: text, source: source)
        let request = try await makeAPIRequest(
            baseURL: bffURL,
            path: "/ingest/structure/suggest",
            method: "POST",
            body: try encodeJSONBody(body)
        )
        return try await self.request(
            request,
            decode: StructureSuggestResult.self,
            decoder: StructureJSON.decoder,
            successStatusCodes: 200...200
        )
    }

    /// POST `/v1/ingest/structure/apply`
    func applyStructure(_ request: ApplyStructureRequest) async throws -> ApplyStructureResult {
        let apiRequest = try await makeAPIRequest(
            baseURL: bffURL,
            path: "/ingest/structure/apply",
            method: "POST",
            body: try request.jsonData()
        )
        return try await self.request(
            apiRequest,
            decode: ApplyStructureResult.self,
            decoder: StructureJSON.decoder,
            successStatusCodes: 200...200
        )
    }
}
