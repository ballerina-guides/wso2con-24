import ballerina/graphql;
import ballerina/graphql.dataloader;
import ballerina/http;
import ballerina/log;

import xlibb/pubsub;

const USER_ID = "userId";

configurable boolean graphiqlEnabled = false;
configurable boolean introspection = false;
configurable int maxQueryDepth = 15;
configurable string[] allowOrigins = ["http://localhost:3000"];

final http:Client geoClient = check getGeoClient();

function getGeoClient() returns http:Client|error => new ("https://public.opendatasoft.com/api/explore/v2.1/catalog/datasets");

final pubsub:PubSub subscriptions = new;

@graphql:ServiceConfig {
    graphiql: {
        enabled: graphiqlEnabled
    },
    cacheConfig: {},
    introspection,
    maxQueryDepth,
    contextInit,
    cors: {
        allowOrigins
    }
}
service /reviewed on new graphql:Listener(9000,
        secureSocket = {
            key: {
                certFile: "../resources/certs/public.crt",
                keyFile: "../resources/certs/private.key"
            }
        }) {

    resource function get places(string? city = (), string? country = (), boolean sortByRating = false) returns Place[] {
        Place[] filteredPlaces = getFilteredPlaces(city, country);
        if sortByRating {
            return from Place place in filteredPlaces
                order by place.getRating() descending
                select place;
        }
        return from Place place in filteredPlaces
            order by place.getName()
            select place;
    }

    resource function get place(@graphql:ID int placeId) returns Place {
        return getPlace(placeId);
    }

    resource function get author(@graphql:ID int authorId) returns Author {
        return new (authorId);
    }

    remote function addReview(ReviewInput reviewInput) returns Review {
        int id = reviews.nextKey();
        ReviewData reviewData = {id, ...reviewInput};
        reviews.add(reviewData);
        pubsub:Error? status = subscriptions.publish(reviewData.placeId.toString(), id);
        if status is pubsub:Error {
            log:printError("Error publishing review update", data = reviewData);
        }
        return new (id);
    }

    @graphql:ResourceConfig {
        interceptors: new AuthInterceptor()
    }
    remote function addPlace(PlaceInput placeInput) returns Place|error {
        int id = places.nextKey();
        PlaceData placeData = {id, ...placeInput};
        places.add(placeData);
        return getPlace(id);
    }

    resource function subscribe reviews(int placeId) returns stream<Review, error?>|error {
        stream<int, error?> reviews = check subscriptions.subscribe(placeId.toString());
        return from int reviewId in reviews select new (reviewId);
    }
}

type CityDataResultsItem record {
    int population;
    string timezone;
};

type CityData record {
    int total_count;
    CityDataResultsItem[] results;
};

isolated function getCityData(string city, string country) returns CityDataResultsItem|error {
    CityData cityData = check geoClient->get(
        string `/geonames-all-cities-with-a-population-500/records?refine=name:${
            city}&refine=country:${country}`);

    if cityData.total_count == 0 {
        return error(string `cannot find data for ${city}, ${country}`);
    }

    // Assume the entry with the highest population is the most correct one.
    CityDataResultsItem[] results = cityData.results;
    int[] populationValues = from CityDataResultsItem {population} in results select population;
    int max = int:max(populationValues[0], ...populationValues.slice(1));
    int indexOfEntryWithHighestPopulation = check populationValues.indexOf(max).ensureType();
    return results[indexOfEntryWithHighestPopulation];
}

type Place distinct service object {
    function getName() returns string;
    
    function getRating() returns decimal?;

    resource function get id() returns @graphql:ID int;

    resource function get name() returns string;

    resource function get city() returns string;

    resource function get country() returns string;

    resource function get population(graphql:Context ctx) returns int|error?;

    resource function get timezone(graphql:Context ctx) returns string|error?;

    resource function get reviews() returns Review[];

    resource function get rating() returns decimal?;
};

// With union.
// type Place PlaceWithEntranceFee|PlaceWithFreeEntrance;

distinct service class PlaceWithFreeEntrance {
    *Place;

    final int id;
    final string name;
    final string city;
    final string country;

    function init(@graphql:ID int id) {
        PlaceData placeData = places.get(id);
        self.id = id;
        self.name = placeData.name;
        self.city = placeData.city;
        self.country = placeData.country;
    }

    function getName() returns string => self.name;
    
    function getRating() returns decimal? {
        return from ReviewData {placeId, rating} in reviews
            where placeId == self.id
            collect avg(rating);
    }

    resource function get id() returns @graphql:ID int => self.id;

    resource function get name() returns string => self.getName();

    resource function get city() returns string => self.city;

    resource function get country() returns string => self.country;

    isolated function cityDataPreLoader(graphql:Context ctx) {
        dataloader:DataLoader bookLoader = ctx.getDataLoader("cityDataLoader");
        bookLoader.add([self.city, self.country]);
    }

    @graphql:ResourceConfig {
        prefetchMethodName: "cityDataPreLoader"
    }
    resource function get population(graphql:Context ctx) returns int|error? {
        dataloader:DataLoader cityDataLoader = ctx.getDataLoader("cityDataLoader");
        CityDataResultsItem cityData = check cityDataLoader.get([self.city, self.country]);
        return cityData.population;
    }

    @graphql:ResourceConfig {
        prefetchMethodName: "cityDataPreLoader"
    }
    resource function get timezone(graphql:Context ctx) returns string|error? {
        dataloader:DataLoader cityDataLoader = ctx.getDataLoader("cityDataLoader");
        CityDataResultsItem cityData = check cityDataLoader.get([self.city, self.country]);
        return cityData.timezone;
    }

    resource function get reviews() returns Review[] {
        return from ReviewData reviewData in reviews
            where reviewData.placeId == self.id
            select new (reviewData.id);
    }

    resource function get rating() returns decimal? => self.getRating();
}

distinct service class PlaceWithEntranceFee {
    *Place;

    final int id;
    final string name;
    final string city;
    final string country;
    final decimal fee;

    function init(@graphql:ID int id) {
        PlaceData placeData = places.get(id);
        self.id = id;
        self.name = placeData.name;
        self.city = placeData.city;
        self.country = placeData.country;
        self.fee = placeData.entryFee;
    }

    function getName() returns string => self.name;
    
    function getRating() returns decimal? {
        return from ReviewData {placeId, rating} in reviews
            where placeId == self.id
            collect avg(rating);
    }

    resource function get id() returns @graphql:ID int => self.id;

    resource function get name() returns string => self.getName();

    resource function get city() returns string => self.city;

    resource function get country() returns string => self.country;

    isolated function cityDataPreLoader(graphql:Context ctx) {
        dataloader:DataLoader bookLoader = ctx.getDataLoader("cityDataLoader");
        bookLoader.add([self.city, self.country]);
    }

    @graphql:ResourceConfig {
        prefetchMethodName: "cityDataPreLoader"
    }
    resource function get population(graphql:Context ctx) returns int|error? {
        dataloader:DataLoader cityDataLoader = ctx.getDataLoader("cityDataLoader");
        CityDataResultsItem cityData = check cityDataLoader.get([self.city, self.country]);
        return cityData.population;
    }

    @graphql:ResourceConfig {
        prefetchMethodName: "cityDataPreLoader"
    }
    resource function get timezone(graphql:Context ctx) returns string|error? {
        dataloader:DataLoader cityDataLoader = ctx.getDataLoader("cityDataLoader");
        CityDataResultsItem cityData = check cityDataLoader.get([self.city, self.country]);
        return cityData.timezone;
    }

    resource function get reviews() returns Review[] {
        return from ReviewData reviewData in reviews
            where reviewData.placeId == self.id
            select new (reviewData.id);
    }

    resource function get rating() returns decimal? => self.getRating();

    resource function get fee() returns decimal => self.fee;
}

public service class Review {
    final int id;
    final int rating;
    final string content;
    final int placeId;
    final int authorId;

    function init(@graphql:ID int id) {
        ReviewData reviewData = reviews.get(id);
        self.id = id;
        self.rating = reviewData.rating;
        self.content = reviewData.content;
        self.placeId = reviewData.placeId;
        self.authorId = reviewData.authorId;
    }

    resource function get id() returns @graphql:ID int => self.id;

    resource function get rating() returns int => self.rating;

    resource function get content() returns string => self.content;

    resource function get place() returns Place =>
        getPlace(self.placeId);

    resource function get author() returns Author =>
        new (self.authorId);
}

service class Author {
    final int id;
    final string username;

    function init(@graphql:ID int id) {
        self.id = id;
        self.username = authors.get(id).username;
    }

    resource function get id() returns @graphql:ID int => self.id;

    resource function get username() returns string => self.username;

    resource function get reviews() returns Review[] {
        return from ReviewData reviewData in reviews
            where reviewData.authorId == self.id
            select new Review(reviewData.id);
    }
}

type ReviewInput record {|
    int rating;
    string content;
    int placeId;
    int authorId;
|};

type PlaceInput record {|
    string name;
    string city;
    string country;
    decimal entryFee;
|};

function getPlace(int placeId) returns Place {
    decimal entryFee = places.get(placeId).entryFee;
    return entryFee == 0d ?
        new PlaceWithFreeEntrance(placeId) :
        new PlaceWithEntranceFee(placeId);
}

isolated function cityDataLoaderFunction(readonly & anydata[] ids) returns CityDataResultsItem[]|error {
    [string, string][] cities = check ids.ensureType();
    return from [string, string] [city, country] in cities
        select check getCityData(city, country);
}

isolated function contextInit(http:RequestContext requestContext, http:Request request) returns graphql:Context|error {
    graphql:Context ctx = new;

    string|http:HeaderNotFoundError userId = request.getHeader(USER_ID);
    ctx.set(USER_ID, userId is http:HeaderNotFoundError ? () : check int:fromString(userId));
    ctx.registerDataLoader("cityDataLoader", new dataloader:DefaultDataLoader(cityDataLoaderFunction));
    return ctx;
}

readonly service class AuthInterceptor {
    *graphql:Interceptor;

    isolated remote function execute(graphql:Context context, graphql:Field 'field) returns anydata|error {
        check validateAdminRole(context);
        return context.resolve('field);
    }
}

// Mock function for role validation.
isolated function validateAdminRole(graphql:Context context) returns error? {
    int|error userId = context.get(USER_ID).ensureType();
    if userId is int && userId is 5002|5003 {
        return ();
    }
    return error("Forbidden");
}

function getFilteredPlaces(string? filterCity, string? filterCountry) returns Place[] {
    if filterCity is string && filterCountry is string {
        return from PlaceData {id, city, country} in places
            where city == filterCity && country == filterCountry
            select getPlace(id);
    }

    if filterCity is string {
        return from PlaceData {id, city} in places
            where city == filterCity
            select getPlace(id);
    }

    if filterCountry is string {
        return from PlaceData {id, country} in places
            where country == filterCountry
            select getPlace(id);
    }

    return from PlaceData {id} in places select getPlace(id);
}
