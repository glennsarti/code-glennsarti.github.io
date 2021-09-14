package gatlingBlog

import scala.concurrent.duration._

import io.gatling.core.Predef._
import io.gatling.http.Predef._

class SartiDevSimulation1 extends Simulation {
  val httpProtocol = http
    .baseUrl("https://sarti.dev")

  val scn = scenario("SendSimpleQuery")
    .exec(
      http("root_request")
        .get("/")
    )

  setUp(scn.inject(
    //atOnceUsers(100)
    constantConcurrentUsers(100).during(10.minutes)
  ).protocols(httpProtocol))
}
