//
//  MileageRates.swift
//  MileageTrackeriOS
//
//  Created by Harry Just on 04/05/2026.
//

struct OfficalMileageRate {
    let countryCode: String
    let defaultDistanceUnit: DistanceUnit
    let mileageRates: [MileageRates]
}

let officialRates: [OfficalMileageRate] = [
    .init(
        countryCode: "NZ",
        defaultDistanceUnit: .kilometres,
        mileageRates: [
            .init(
                name: "Diesel",
                fuelType: [.diesel],
                thresholds: [
                    .init(centsPerKm: 0.79, lowerBound: 0, upperBound: 140000)
                ]
            ),
            .init(
                name: "petrol",
                fuelType: [.petrol],
                thresholds: [
                    .init(centsPerKm: 1, lowerBound: 0, upperBound: 140000)
                ]
            )
        ]
    )
]
