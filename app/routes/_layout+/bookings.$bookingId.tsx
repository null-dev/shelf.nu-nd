import { json } from "@remix-run/node";
import type {
  ActionFunctionArgs,
  MetaFunction,
  LoaderFunctionArgs,
} from "@remix-run/node";
import { useLoaderData } from "@remix-run/react";
import { useAtomValue } from "jotai";
import { parseFormAny } from "react-zorm";
import { dynamicTitleAtom } from "~/atoms/dynamic-title-atom";
import { BookingForm, NewBookingFormSchema } from "~/components/booking";
import ContextualModal from "~/components/layout/contextual-modal";
import Header from "~/components/layout/header";
import type { HeaderData } from "~/components/layout/header/types";
import { Badge } from "~/components/shared";
import { db } from "~/database";
import { commitAuthSession, requireAuthSession } from "~/modules/auth";
import { getBooking, upsertBooking } from "~/modules/booking";
import type { ExtendedBooking } from "~/modules/booking/types";
import {
  requireOrganisationId,
  setSelectedOrganizationIdCookie,
} from "~/modules/organization/context.server";
import {
  assertIsPost,
  generatePageMeta,
  getCurrentSearchParams,
  getParamsValues,
  getRequiredParam,
} from "~/utils";
import { appendToMetaTitle } from "~/utils/append-to-meta-title";
import {
  setCookie,
  updateCookieWithPerPage,
  userPrefs,
} from "~/utils/cookies.server";
import { dateForDateTimeInputValue } from "~/utils/date-fns";
import { sendNotification } from "~/utils/emitter/send-notification.server";
import { ShelfStackError } from "~/utils/error";
import { bookingStatusColorMap } from "./bookings._index";

export async function loader({ request, params }: LoaderFunctionArgs) {
  const authSession = await requireAuthSession(request);
  const { organizationId } = await requireOrganisationId(authSession, request);
  const bookingId = getRequiredParam(params, "bookingId");

  const teamMembers = await db.teamMember.findMany({
    where: {
      deletedAt: null,
      organizationId,
    },
    include: {
      user: true,
    },
    orderBy: {
      userId: "asc",
    },
  });
  const booking = await getBooking({ id: bookingId });

  if (!booking) {
    throw new ShelfStackError({ message: "Booking not found", status: 404 });
  }

  const searchParams = getCurrentSearchParams(request);
  const { page, perPageParam } = getParamsValues(searchParams);
  const cookie = await updateCookieWithPerPage(request, perPageParam);
  const { perPage } = cookie;
  const modelName = {
    singular: "asset",
    plural: "assets",
  };
  const totalItems = 0;
  const totalPages = 1 / perPage;
  const { prev, next } = generatePageMeta(request);

  const header: HeaderData = {
    title: `Edit | ${booking.name}`,
  };

  if (booking.from) {
    Object.assign(booking, {
      fromForDateInput: dateForDateTimeInputValue(booking.from),
    });
  }
  if (booking.to) {
    Object.assign(booking, {
      toForDateInput: dateForDateTimeInputValue(booking.to),
    });
  }

  return json(
    {
      header,
      booking: booking as ExtendedBooking,
      modelName,
      items: booking.assets,
      page,
      totalItems,
      perPage,
      totalPages,
      next,
      prev,
      teamMembers,
    },
    {
      headers: {
        "Set-Cookie": await userPrefs.serialize(cookie),
      },
    }
  );
}

export const meta: MetaFunction<typeof loader> = ({ data }) => [
  { title: data ? appendToMetaTitle(data.header.title) : "" },
];

export const handle = {
  breadcrumb: () => "Edit",
};

export async function action({ request, params }: ActionFunctionArgs) {
  assertIsPost(request);
  const authSession = await requireAuthSession(request);
  const { organizationId } = await requireOrganisationId(authSession, request);
  const id = getRequiredParam(params, "bookingId");

  const formData = await request.formData();
  const result = await NewBookingFormSchema.safeParseAsync(
    parseFormAny(formData)
  );

  if (!result.success) {
    return json(
      {
        errors: result.error,
        success: false,
      },
      {
        status: 400,
        headers: {
          "Set-Cookie": await commitAuthSession(request, { authSession }),
        },
      }
    );
  }
  const intent = formData.get("intent") as "save" | "reserve";
  const { name, startDate, endDate, custodian } = result.data;

  switch (intent) {
    case "save":
      const booking = await upsertBooking({
        custodianTeamMemberId: custodian,
        organizationId,
        id,
        name,
        from: startDate,
        to: endDate,
      });

      sendNotification({
        title: "Booking saved",
        message: "Your booking has been saved successfully",
        icon: { name: "success", variant: "success" },
        senderId: authSession.userId,
      });
      return json(
        { booking },
        {
          status: 200,
          headers: [
            setCookie(await commitAuthSession(request, { authSession })),
            setCookie(await setSelectedOrganizationIdCookie(organizationId)),
          ],
        }
      );
    case "reserve":
      return null;
    default:
      return null;
  }
}

export default function BookingEditPage() {
  const name = useAtomValue(dynamicTitleAtom);
  const hasName = name !== "";
  const { booking, teamMembers } = useLoaderData<typeof loader>();
  return (
    <>
      <Header title={hasName ? name : booking.name} />
      <div className="mr-auto">
        <Badge color={bookingStatusColorMap[booking.status]}>Draft</Badge>
      </div>
      <div>
        <BookingForm
          id={booking.id}
          name={booking.name}
          startDate={booking.fromForDateInput || undefined}
          endDate={booking.toForDateInput || undefined}
          custodianId={
            booking.custodianTeamMemberId ||
            teamMembers.find(
              (member) => member.user?.id === booking.custodianUserId
            )?.id
          }
        />
        <ContextualModal />
      </div>
    </>
  );
}
